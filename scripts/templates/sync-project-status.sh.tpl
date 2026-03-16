#!/usr/bin/env bash
set -euo pipefail

# ステータス自動同期スクリプト
# Issue/PR のライフサイクルイベントに連動して GitHub Project のステータスを自動更新する。
#
# このスクリプトはセットアップワークフロー（⑥）によって対象リポジトリに配置される。
# 対象リポジトリで単独動作するため、共通ライブラリには依存しない。
#
# 環境変数（ワークフローから渡される）:
#   GH_TOKEN       - GitHub PAT（Projects 操作権限）
#   EVENT_NAME     - github.event_name
#   ACTION         - github.event.action
#   ISSUE_NODE_ID  - github.event.issue.node_id
#   PR_NODE_ID     - github.event.pull_request.node_id
#   PR_MERGED      - github.event.pull_request.merged
#   REVIEW_STATE   - github.event.review.state
#   ISSUE_NUMBER   - github.event.issue.number
#   ISSUE_TITLE    - github.event.issue.title
#   PR_NUMBER      - github.event.pull_request.number
#   PR_TITLE       - github.event.pull_request.title

# --- ステータス順序定義 ---

declare -A STATUS_ORDER=(
  ["Backlog"]=1
  ["Todo"]=2
  ["In Progress"]=3
  ["In Review"]=4
  ["Done"]=5
)

# --- 前方遷移ガード ---

is_forward_transition() {
  local current="$1"
  local target="$2"

  # 同じステータスへの遷移はスキップ
  if [[ "${current}" == "${target}" ]]; then
    return 1
  fi

  # 例外: In Review → In Progress（差し戻し）
  if [[ "${current}" == "In Review" && "${target}" == "In Progress" ]]; then
    return 0
  fi

  # 例外: Done → Todo（再オープン）
  if [[ "${current}" == "Done" && "${target}" == "Todo" ]]; then
    return 0
  fi

  local current_order="${STATUS_ORDER[${current}]:-0}"
  local target_order="${STATUS_ORDER[${target}]:-0}"

  [[ "${target_order}" -gt "${current_order}" ]]
}

# --- Markdown サニタイズ ---
# Job Summary のテーブル出力で | やバッククォートによる崩れを防ぐ

sanitize_for_markdown() {
  local value="$1"
  value="${value//|/\\|}"
  value="${value//\`/}"
  printf '%s' "${value}"
}

# --- イベント解析 ---

echo ""
echo "イベントを解析しています..."
echo "  イベント: ${EVENT_NAME}"
echo "  アクション: ${ACTION}"

NODE_ID=""
TARGET_STATUS=""
LINKED_ISSUE_TARGET_STATUS=""
ITEM_LABEL=""

case "${EVENT_NAME}" in
  issues)
    NODE_ID="${ISSUE_NODE_ID}"
    ITEM_LABEL="#${ISSUE_NUMBER} ${ISSUE_TITLE}"
    case "${ACTION}" in
      opened)    TARGET_STATUS="Backlog" ;;
      closed)    TARGET_STATUS="Done" ;;
      reopened)  TARGET_STATUS="Todo" ;;
      *)
        echo "  対象外のアクションです。スキップします。"
        exit 0
        ;;
    esac
    ;;
  pull_request)
    NODE_ID="${PR_NODE_ID}"
    ITEM_LABEL="#${PR_NUMBER} ${PR_TITLE}"
    case "${ACTION}" in
      opened)
        TARGET_STATUS="In Progress"
        LINKED_ISSUE_TARGET_STATUS="In Progress"
        ;;
      review_requested)    TARGET_STATUS="In Review" ;;
      converted_to_draft)  TARGET_STATUS="In Progress" ;;
      ready_for_review)    TARGET_STATUS="In Review" ;;
      closed)
        TARGET_STATUS="Done"
        # 紐付け Issue の連動更新はマージ時のみ（未マージ close では Issue は閉じられないため）
        if [[ "${PR_MERGED}" == "true" ]]; then
          LINKED_ISSUE_TARGET_STATUS="Done"
        fi
        ;;
      *)
        echo "  対象外のアクションです。スキップします。"
        exit 0
        ;;
    esac
    ;;
  pull_request_review)
    NODE_ID="${PR_NODE_ID}"
    ITEM_LABEL="#${PR_NUMBER} ${PR_TITLE}"
    case "${REVIEW_STATE}" in
      changes_requested)
        TARGET_STATUS="In Progress"
        LINKED_ISSUE_TARGET_STATUS="In Progress"
        ;;
      *)
        echo "  レビュー状態 '${REVIEW_STATE}' はステータス変更対象外です。スキップします。"
        exit 0
        ;;
    esac
    ;;
  *)
    echo "::error::不明なイベント: ${EVENT_NAME}"
    exit 1
    ;;
esac

if [[ -z "${NODE_ID}" ]]; then
  echo "::error::対象ノードの Node ID を取得できませんでした。"
  exit 1
fi

echo "  遷移先ステータス: ${TARGET_STATUS}"
echo "  対象: ${ITEM_LABEL}"

# --- Project Item 取得用 GraphQL クエリ ---

QUERY_GET_PROJECT_ITEMS='
query($nodeId: ID!) {
  node(id: $nodeId) {
    ... on Issue {
      projectItems(first: 100) {
        nodes {
          id
          project {
            id
            number
            field(name: "Status") {
              ... on ProjectV2SingleSelectField {
                id
                options { id name }
              }
            }
          }
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
            }
          }
        }
      }
    }
    ... on PullRequest {
      projectItems(first: 100) {
        nodes {
          id
          project {
            id
            number
            field(name: "Status") {
              ... on ProjectV2SingleSelectField {
                id
                options { id name }
              }
            }
          }
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
            }
          }
        }
      }
    }
  }
}
'

# --- 紐付け Issue 取得用 GraphQL クエリ ---

QUERY_GET_LINKED_ISSUES='
query($prNodeId: ID!) {
  node(id: $prNodeId) {
    ... on PullRequest {
      closingIssuesReferences(first: 50) {
        totalCount
        nodes {
          id
          number
          title
          projectItems(first: 100) {
            nodes {
              id
              project {
                id
                number
                field(name: "Status") {
                  ... on ProjectV2SingleSelectField {
                    id
                    options { id name }
                  }
                }
              }
              fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                }
              }
            }
          }
        }
      }
    }
  }
}
'

# --- ステータス更新用 GraphQL ミューテーション ---

MUTATION_UPDATE_STATUS='
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { singleSelectOptionId: $optionId }
  }) {
    projectV2Item { id }
  }
}
'

# --- ステータス更新関数 ---
# 引数: $1=ノードID, $2=遷移先ステータス, $3=ラベル（ログ用）
# Project Items の JSON を取得し、各プロジェクトに対して前方遷移ガードを適用してステータスを更新する
update_status_for_node() {
  local node_id="$1"
  local target_status="$2"
  local label="$3"

  local updated=0
  local skipped=0
  local not_found=0

  echo ""
  echo "  ${label} の Project Item を取得しています..."

  local result
  if ! result=$(gh api graphql -f query="${QUERY_GET_PROJECT_ITEMS}" -f nodeId="${node_id}" 2>&1); then
    echo "::warning::${label} の Project Item 取得に失敗しました: ${result}"
    return 1
  fi

  # GraphQL エラーチェック
  if echo "${result}" | jq -e '.errors and (.errors | length > 0)' >/dev/null 2>&1; then
    local errors
    errors=$(echo "${result}" | jq -c '.errors')
    echo "::warning::${label} の Project Item 取得で GraphQL エラー: ${errors}"
    return 1
  fi

  # Project Items を取得（Issue / PullRequest どちらにも対応）
  local items
  items=$(echo "${result}" | jq -r '
    .data.node.projectItems.nodes // [] | .[]
  ' 2>/dev/null)

  local item_count
  item_count=$(echo "${result}" | jq -r '
    .data.node.projectItems.nodes // [] | length
  ')

  if [[ "${item_count}" -eq 0 ]]; then
    echo "    Project に属していません。スキップします。"
    return 0
  fi

  echo "    ${item_count} 件の Project Item が見つかりました。"

  # 各 Project Item に対してステータス更新
  for i in $(seq 0 $((item_count - 1))); do
    local item_json
    item_json=$(echo "${result}" | jq -r ".data.node.projectItems.nodes[${i}]")

    local item_id project_id project_number field_id current_status
    item_id=$(echo "${item_json}" | jq -r '.id')
    project_id=$(echo "${item_json}" | jq -r '.project.id')
    project_number=$(echo "${item_json}" | jq -r '.project.number')
    field_id=$(echo "${item_json}" | jq -r '.project.field.id')
    current_status=$(echo "${item_json}" | jq -r '.fieldValueByName.name // "unknown"')

    echo ""
    echo "    Project #${project_number}: ${current_status} → ${target_status}"

    # フィールドID が取得できない場合はスキップ
    if [[ -z "${field_id}" || "${field_id}" == "null" ]]; then
      echo "      Status フィールドが見つかりません。スキップします。"
      not_found=$((not_found + 1))
      continue
    fi

    # 前方遷移ガード
    if [[ "${current_status}" != "unknown" ]] && ! is_forward_transition "${current_status}" "${target_status}"; then
      echo "      前方遷移ガード: 更新をスキップします。"
      skipped=$((skipped + 1))
      continue
    fi

    # 遷移先ステータスの Option ID を解決
    local option_id
    option_id=$(echo "${item_json}" | jq -r \
      --arg status "${target_status}" \
      '.project.field.options[] | select(.name == $status) | .id')

    if [[ -z "${option_id}" ]]; then
      echo "      ステータス '${target_status}' の Option ID が見つかりません。スキップします。"
      not_found=$((not_found + 1))
      continue
    fi

    # ステータス更新
    local update_result
    if ! update_result=$(gh api graphql \
      -f query="${MUTATION_UPDATE_STATUS}" \
      -f projectId="${project_id}" \
      -f itemId="${item_id}" \
      -f fieldId="${field_id}" \
      -f optionId="${option_id}" 2>&1); then
      echo "::warning::ステータス更新に失敗しました（Project #${project_number}）: ${update_result}"
      continue
    fi

    if echo "${update_result}" | jq -e '.errors and (.errors | length > 0)' >/dev/null 2>&1; then
      local errors
      errors=$(echo "${update_result}" | jq -c '.errors')
      echo "::warning::ステータス更新で GraphQL エラー（Project #${project_number}）: ${errors}"
      continue
    fi

    echo "      更新しました。"
    updated=$((updated + 1))
  done

  echo ""
  echo "    結果: 更新=${updated}, スキップ=${skipped}, 未検出=${not_found}"
  return 0
}

# --- メイン処理: 対象アイテムのステータス更新 ---

echo ""
echo "========================================="
echo "  ステータス更新"
echo "========================================="

update_status_for_node "${NODE_ID}" "${TARGET_STATUS}" "${ITEM_LABEL}"

# --- 紐付け Issue の連動更新 ---

LINKED_ISSUES_SUMMARY=""

if [[ -n "${LINKED_ISSUE_TARGET_STATUS}" && "${EVENT_NAME}" != "issues" ]]; then
  echo ""
  echo "========================================="
  echo "  紐付け Issue の連動更新"
  echo "========================================="

  PR_FOR_LINKED="${PR_NODE_ID}"

  echo ""
  echo "紐付け Issue を取得しています..."

  LINKED_RESULT=""
  if ! LINKED_RESULT=$(gh api graphql -f query="${QUERY_GET_LINKED_ISSUES}" -f prNodeId="${PR_FOR_LINKED}" 2>&1); then
    echo "::warning::紐付け Issue の取得に失敗しました: ${LINKED_RESULT}"
  else
    # GraphQL エラーチェック
    if echo "${LINKED_RESULT}" | jq -e '.errors and (.errors | length > 0)' >/dev/null 2>&1; then
      errors=$(echo "${LINKED_RESULT}" | jq -c '.errors')
      echo "::warning::紐付け Issue の取得で GraphQL エラー: ${errors}"
    else
      TOTAL_COUNT=$(echo "${LINKED_RESULT}" | jq -r '.data.node.closingIssuesReferences.totalCount // 0')
      LINKED_COUNT=$(echo "${LINKED_RESULT}" | jq -r '.data.node.closingIssuesReferences.nodes // [] | length')

      if [[ "${TOTAL_COUNT}" -gt 50 ]]; then
        echo "::warning::紐付け Issue が 50 件を超えています（${TOTAL_COUNT} 件）。最初の 50 件のみ処理します。"
      fi

      if [[ "${LINKED_COUNT}" -eq 0 ]]; then
        echo "  紐付け Issue はありません。"
      else
        echo "  ${LINKED_COUNT} 件の紐付け Issue が見つかりました。"

        for j in $(seq 0 $((LINKED_COUNT - 1))); do
          local_issue_json=$(echo "${LINKED_RESULT}" | jq -r ".data.node.closingIssuesReferences.nodes[${j}]")
          local_issue_id=$(echo "${local_issue_json}" | jq -r '.id')
          local_issue_number=$(echo "${local_issue_json}" | jq -r '.number')
          local_issue_title=$(echo "${local_issue_json}" | jq -r '.title')
          local_label="#${local_issue_number} ${local_issue_title}"

          echo ""
          echo "  紐付け Issue: ${local_label}"

          update_status_for_node "${local_issue_id}" "${LINKED_ISSUE_TARGET_STATUS}" "${local_label}"

          LINKED_ISSUES_SUMMARY="${LINKED_ISSUES_SUMMARY}| #${local_issue_number} | ${LINKED_ISSUE_TARGET_STATUS} |
"
        done
      fi
    fi
  fi
fi

# --- Job Summary 出力 ---

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## ステータス自動同期 完了"
    echo ""
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    SAFE_ITEM_LABEL=$(sanitize_for_markdown "${ITEM_LABEL}")
    echo "| イベント | \`${EVENT_NAME}.${ACTION}\` |"
    echo "| 対象 | \`${SAFE_ITEM_LABEL}\` |"
    echo "| ステータス遷移 | → ${TARGET_STATUS} |"

    if [[ -n "${LINKED_ISSUES_SUMMARY}" ]]; then
      echo ""
      echo "### 紐付け Issue の連動更新"
      echo ""
      echo "| Issue | 遷移先 |"
      echo "|-------|--------|"
      echo -n "${LINKED_ISSUES_SUMMARY}"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi

echo ""
echo "========================================="
echo "  完了サマリー"
echo "========================================="
echo "  イベント:     ${EVENT_NAME}.${ACTION}"
echo "  対象:         ${ITEM_LABEL}"
echo "  遷移先:       ${TARGET_STATUS}"
echo "========================================="
echo ""
echo "ステータス同期が完了しました。"
