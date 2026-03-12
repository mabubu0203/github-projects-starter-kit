#!/usr/bin/env bash
set -euo pipefail

# GitHub Project アイテム エクスポートスクリプト
# https://mabubu0203.github.io/github-projects-starter-kit/scripts/export-project-items
#
# 環境変数:
#   GH_TOKEN       - GitHub PAT（Projects 読み取り権限が必要）
#   PROJECT_OWNER  - Project の所有者
#   PROJECT_NUMBER - 対象 Project の Number
#   OUTPUT_FORMAT  - 出力形式（markdown / csv / tsv / json、デフォルト: markdown）

# --- 共通ライブラリ読み込み ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- バリデーション ---

require_env "GH_TOKEN" "Secrets に PROJECT_PAT を設定してください。"
require_env "PROJECT_OWNER"
require_env "PROJECT_NUMBER"
validate_project_number
require_command "gh" "GitHub CLI (gh) が必要です。PATH を確認してください。"
require_command "jq" "JSON の解析に必要です。"

OUTPUT_FORMAT="${OUTPUT_FORMAT:-markdown}"
if [[ "${OUTPUT_FORMAT}" != "markdown" && "${OUTPUT_FORMAT}" != "csv" && "${OUTPUT_FORMAT}" != "tsv" && "${OUTPUT_FORMAT}" != "json" ]]; then
  SAFE_FORMAT=$(sanitize_for_workflow_command "${OUTPUT_FORMAT}")
  echo "::error::OUTPUT_FORMAT の値が不正です: ${SAFE_FORMAT}（markdown / csv / tsv / json を指定してください）"
  exit 1
fi

# --- ヘルパー関数 ---

# Project のアイテム一覧を取得する（ページネーション対応）
fetch_project_items() {
  local all_items="[]"
  local cursor=""
  local has_next="true"
  local page=0
  local max_pages=50

  while [[ "${has_next}" == "true" ]]; do
    page=$((page + 1))
    if [[ "${page}" -gt "${max_pages}" ]]; then
      echo "::warning::ページネーション上限（${max_pages} ページ）に達しました。一部のアイテムが取得されていない可能性があります。" >&2
      break
    fi

    local after_clause=""
    if [[ -n "${cursor}" ]]; then
      after_clause=", after: \"${cursor}\""
    fi

    local query
    query=$(cat <<GRAPHQL
query {
  ${OWNER_QUERY_FIELD}(login: "${PROJECT_OWNER}") {
    projectV2(number: ${PROJECT_NUMBER}) {
      title
      items(first: 100${after_clause}) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          content {
            ... on Issue {
              __typename
              number
              title
              url
              state
              createdAt
              updatedAt
              author { login }
              repository { nameWithOwner }
              assignees(first: 10) { nodes { login } }
              labels(first: 10) { nodes { name } }
            }
            ... on PullRequest {
              __typename
              number
              title
              url
              state
              createdAt
              updatedAt
              author { login }
              repository { nameWithOwner }
              assignees(first: 10) { nodes { login } }
              labels(first: 10) { nodes { name } }
            }
          }
        }
      }
    }
  }
}
GRAPHQL
)

    local result
    if ! result=$(gh api graphql -f query="${query}" 2>&1); then
      local safe_result
      safe_result=$(sanitize_for_workflow_command "${result}")
      echo "::error::GraphQL API の呼び出しに失敗しました: ${safe_result}" >&2
      return 1
    fi

    # GraphQL エラーチェック
    local errors
    errors=$(echo "${result}" | jq -r '.errors // empty' 2>/dev/null || true)
    if [[ -n "${errors}" ]]; then
      local safe_errors
      safe_errors=$(sanitize_for_workflow_command "${errors}")
      echo "::error::GraphQL エラーが発生しました: ${safe_errors}" >&2
      return 1
    fi

    # Project タイトル取得（初回のみ）
    if [[ "${page}" -eq 1 ]]; then
      PROJECT_TITLE=$(echo "${result}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.title // \"\"" 2>/dev/null || true)
    fi

    # アイテムを正規化して追加
    local page_items
    page_items=$(echo "${result}" | jq "[.data.${OWNER_QUERY_FIELD}.projectV2.items.nodes[] | select(.content != null) | select(.content.__typename != null) | {
      type: .content.__typename,
      number: .content.number,
      title: .content.title,
      url: .content.url,
      state: .content.state,
      repository: .content.repository.nameWithOwner,
      author: (.content.author.login // \"\"),
      assignees: ([.content.assignees.nodes[].login] | join(\", \")),
      labels: ([.content.labels.nodes[].name] | join(\", \")),
      created_at: .content.createdAt,
      updated_at: .content.updatedAt
    }]" 2>/dev/null || echo "[]")

    local page_count
    page_count=$(echo "${page_items}" | jq 'length')
    echo "  ページ ${page} 取得完了（${page_count} 件）" >&2

    all_items=$(echo "${all_items}" "${page_items}" | jq -s '.[0] + .[1]')

    has_next=$(echo "${result}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.items.pageInfo.hasNextPage" 2>/dev/null || echo "false")
    cursor=$(echo "${result}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.items.pageInfo.endCursor // empty" 2>/dev/null || true)
  done

  echo "${all_items}"
}

# --- フォーマッター関数 ---

format_markdown() {
  local items="$1"
  local issue_count pr_count
  issue_count=$(echo "${items}" | jq '[.[] | select(.type == "Issue")] | length')
  pr_count=$(echo "${items}" | jq '[.[] | select(.type == "PullRequest")] | length')

  {
    echo "# Project アイテム一覧"
    echo ""
    echo "- **Project:** ${PROJECT_TITLE}"
    echo "- **Project Number:** ${PROJECT_NUMBER}"
    echo "- **Issue:** ${issue_count} 件"
    echo "- **Pull Request:** ${pr_count} 件"
    echo "- **合計:** $((issue_count + pr_count)) 件"
    echo ""

    if [[ "${issue_count}" -gt 0 ]]; then
      echo "## Issues"
      echo ""
      echo "| # | タイトル | 状態 | リポジトリ | 作成者 | アサイン | ラベル | 作成日 | 更新日 |"
      echo "|---|---------|------|-----------|--------|---------|--------|--------|--------|"
      echo "${items}" | jq -r '.[] | select(.type == "Issue") | "| [#\(.number)](\(.url)) | \(.title | gsub("\\|"; "\\|")) | \(.state) | \(.repository) | \(.author) | \(.assignees) | \(.labels) | \(.created_at | split("T")[0]) | \(.updated_at | split("T")[0]) |"'
      echo ""
    fi

    if [[ "${pr_count}" -gt 0 ]]; then
      echo "## Pull Requests"
      echo ""
      echo "| # | タイトル | 状態 | リポジトリ | 作成者 | アサイン | ラベル | 作成日 | 更新日 |"
      echo "|---|---------|------|-----------|--------|---------|--------|--------|--------|"
      echo "${items}" | jq -r '.[] | select(.type == "PullRequest") | "| [#\(.number)](\(.url)) | \(.title | gsub("\\|"; "\\|")) | \(.state) | \(.repository) | \(.author) | \(.assignees) | \(.labels) | \(.created_at | split("T")[0]) | \(.updated_at | split("T")[0]) |"'
      echo ""
    fi
  }
}

format_csv() {
  local items="$1"
  echo "type,number,title,url,state,repository,author,assignees,labels,created_at,updated_at"
  echo "${items}" | jq -r '.[] | [.type, .number, .title, .url, .state, .repository, .author, .assignees, .labels, .created_at, .updated_at] | @csv'
}

format_tsv() {
  local items="$1"
  echo -e "type\tnumber\ttitle\turl\tstate\trepository\tauthor\tassignees\tlabels\tcreated_at\tupdated_at"
  echo "${items}" | jq -r '.[] | [.type, (.number | tostring), .title, .url, .state, .repository, .author, .assignees, .labels, .created_at, .updated_at] | @tsv'
}

format_json() {
  local items="$1"
  echo "${items}" | jq '.'
}

# --- オーナータイプ判定 ---

detect_owner_type

# --- アイテム取得 ---

echo ""
echo "Project #${PROJECT_NUMBER} のアイテムを取得しています..."
PROJECT_TITLE=""
ITEMS=$(fetch_project_items)

TOTAL_COUNT=$(echo "${ITEMS}" | jq 'length')
ISSUE_COUNT=$(echo "${ITEMS}" | jq '[.[] | select(.type == "Issue")] | length')
PR_COUNT=$(echo "${ITEMS}" | jq '[.[] | select(.type == "PullRequest")] | length')

echo "  合計: ${TOTAL_COUNT} 件（Issue: ${ISSUE_COUNT}, PR: ${PR_COUNT}）"

if [[ "${TOTAL_COUNT}" -eq 0 ]]; then
  echo "::warning::対象の Issue / Pull Request が見つかりませんでした。"
fi

# --- フォーマット・出力 ---

echo ""
echo "出力形式: ${OUTPUT_FORMAT}"

case "${OUTPUT_FORMAT}" in
  markdown) FILE_EXT="md" ;;
  csv)      FILE_EXT="csv" ;;
  tsv)      FILE_EXT="tsv" ;;
  json)     FILE_EXT="json" ;;
esac

OUTPUT_FILE="export-${PROJECT_NUMBER}-items.${FILE_EXT}"

case "${OUTPUT_FORMAT}" in
  markdown) format_markdown "${ITEMS}" > "${OUTPUT_FILE}" ;;
  csv)      format_csv "${ITEMS}" > "${OUTPUT_FILE}" ;;
  tsv)      format_tsv "${ITEMS}" > "${OUTPUT_FILE}" ;;
  json)     format_json "${ITEMS}" > "${OUTPUT_FILE}" ;;
esac

echo "ファイル出力: ${OUTPUT_FILE}"

# --- Step Summary ---

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Project アイテム エクスポート 完了"
    echo ""
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| Project Owner | \`${PROJECT_OWNER}\` |"
    echo "| Project Number | ${PROJECT_NUMBER} |"
    echo "| Project Title | ${PROJECT_TITLE} |"
    echo "| 出力形式 | ${OUTPUT_FORMAT} |"
    echo "| Issue 件数 | ${ISSUE_COUNT} 件 |"
    echo "| PR 件数 | ${PR_COUNT} 件 |"
    echo "| **合計** | **${TOTAL_COUNT} 件** |"
    echo ""

    if [[ "${OUTPUT_FORMAT}" == "markdown" ]]; then
      # markdown はそのまま埋め込み（100行まで）
      line_count=$(wc -l < "${OUTPUT_FILE}" | tr -d ' ')
      if [[ "${line_count}" -le 100 ]]; then
        cat "${OUTPUT_FILE}"
      else
        head -100 "${OUTPUT_FILE}"
        echo ""
        echo "> ... 以降省略（全 ${line_count} 行）。完全なデータは artifact からダウンロードしてください。"
      fi
    else
      # csv/tsv/json はコードブロックでプレビュー
      echo "### プレビュー（先頭20行）"
      echo ""
      echo '```'
      head -20 "${OUTPUT_FILE}"
      echo '```'
      echo ""
      echo "> 完全なデータは artifact からダウンロードしてください。"
    fi
  } >> "${GITHUB_STEP_SUMMARY}"
fi

# --- コンソールサマリー ---

echo ""
echo "========================================="
echo "  完了サマリー"
echo "========================================="
echo "  Project:  ${PROJECT_TITLE} (#${PROJECT_NUMBER})"
echo "  形式:     ${OUTPUT_FORMAT}"
echo "  Issue:    ${ISSUE_COUNT} 件"
echo "  PR:       ${PR_COUNT} 件"
echo "  合計:     ${TOTAL_COUNT} 件"
echo "  出力先:   ${OUTPUT_FILE}"
echo "========================================="

echo ""
echo "::notice::Project アイテムのエクスポートが完了しました（${TOTAL_COUNT} 件、形式: ${OUTPUT_FORMAT}）。"
