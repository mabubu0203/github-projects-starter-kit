#!/usr/bin/env bash
set -euo pipefail

# GitHub Project ステータスカラム設定スクリプト
# 環境変数:
#   GH_TOKEN         - GitHub PAT（Projects 操作権限が必要）
#   PROJECT_OWNER    - Project の所有者
#   PROJECT_NUMBER   - 対象 Project の Number
#   TEMPLATE_PATTERN - テンプレートパターン（kanban / sprint / simple、デフォルト: simple）

# --- ヘルパー関数 ---

# GitHub Actions ワークフローコマンドインジェクションを防ぐためのサニタイズ関数
sanitize_for_workflow_command() {
  local value="$1"
  value="${value//'%'/'%25'}"
  value="${value//$'\n'/'%0A'}"
  value="${value//$'\r'/'%0D'}"
  echo "${value}"
}

# テンプレートパターンに応じたステータスカラム定義を返す
# 出力形式: JSON配列（name, color, description のオブジェクト）
get_status_options() {
  local pattern="$1"

  case "${pattern}" in
    kanban)
      cat <<'JSON'
[
  {"name": "Backlog", "color": "GRAY", "description": "未着手のアイテム"},
  {"name": "Todo", "color": "BLUE", "description": "次に取り組むアイテム"},
  {"name": "In Progress", "color": "YELLOW", "description": "作業中のアイテム"},
  {"name": "In Review", "color": "ORANGE", "description": "レビュー中のアイテム"},
  {"name": "Done", "color": "GREEN", "description": "完了したアイテム"}
]
JSON
      ;;
    sprint)
      cat <<'JSON'
[
  {"name": "Sprint Backlog", "color": "GRAY", "description": "スプリントバックログ"},
  {"name": "In Progress", "color": "YELLOW", "description": "作業中のアイテム"},
  {"name": "In Review", "color": "ORANGE", "description": "レビュー中のアイテム"},
  {"name": "Done", "color": "GREEN", "description": "完了したアイテム"},
  {"name": "Blocked", "color": "RED", "description": "ブロックされたアイテム"}
]
JSON
      ;;
    simple)
      cat <<'JSON'
[
  {"name": "Todo", "color": "BLUE", "description": "未着手のアイテム"},
  {"name": "In Progress", "color": "YELLOW", "description": "作業中のアイテム"},
  {"name": "Done", "color": "GREEN", "description": "完了したアイテム"}
]
JSON
      ;;
  esac
}

# --- バリデーション ---

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::GH_TOKEN が設定されていません。Secrets に PROJECT_PAT を設定してください。"
  exit 1
fi

if [[ -z "${PROJECT_OWNER:-}" ]]; then
  echo "::error::PROJECT_OWNER が指定されていません。"
  exit 1
fi

if [[ -z "${PROJECT_NUMBER:-}" ]]; then
  echo "::error::PROJECT_NUMBER が指定されていません。"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "::error::jq がインストールされていません。JSON の解析に必要です。"
  exit 1
fi

TEMPLATE_PATTERN="${TEMPLATE_PATTERN:-simple}"
if [[ "${TEMPLATE_PATTERN}" != "kanban" && "${TEMPLATE_PATTERN}" != "sprint" && "${TEMPLATE_PATTERN}" != "simple" ]]; then
  SAFE_TEMPLATE_PATTERN=$(sanitize_for_workflow_command "${TEMPLATE_PATTERN}")
  echo "::error::TEMPLATE_PATTERN の値が不正です: ${SAFE_TEMPLATE_PATTERN}（kanban / sprint / simple を指定してください）"
  exit 1
fi

# --- オーナータイプ判定 ---

echo "オーナータイプを判定しています..."

if ! OWNER_INFO=$(gh api "users/${PROJECT_OWNER}" --jq '.type' 2>&1); then
  SAFE_OWNER_INFO=$(sanitize_for_workflow_command "${OWNER_INFO}")
  SAFE_PROJECT_OWNER=$(sanitize_for_workflow_command "${PROJECT_OWNER}")
  echo "::error::オーナー情報の取得に失敗しました: ${SAFE_OWNER_INFO}"
  echo "::error::PROJECT_OWNER=${SAFE_PROJECT_OWNER} が正しいか確認してください。"
  exit 1
fi

OWNER_TYPE="${OWNER_INFO}"
echo "  オーナータイプ: ${OWNER_TYPE}"

if [[ "${OWNER_TYPE}" == "User" ]]; then
  OWNER_QUERY_FIELD="user"
elif [[ "${OWNER_TYPE}" == "Organization" ]]; then
  OWNER_QUERY_FIELD="organization"
else
  SAFE_OWNER_TYPE=$(sanitize_for_workflow_command "${OWNER_TYPE}")
  echo "::error::不明なオーナータイプ: ${SAFE_OWNER_TYPE}"
  exit 1
fi

# --- Project ID と Status フィールド情報の取得 ---

echo ""
echo "Project #${PROJECT_NUMBER} の Status フィールドを取得しています..."

FIELD_QUERY=$(cat <<GRAPHQL
query {
  ${OWNER_QUERY_FIELD}(login: "${PROJECT_OWNER}") {
    projectV2(number: ${PROJECT_NUMBER}) {
      id
      fields(first: 50) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
              color
              description
            }
          }
        }
      }
    }
  }
}
GRAPHQL
)

if ! FIELD_RESULT=$(gh api graphql -f query="${FIELD_QUERY}" 2>&1); then
  SAFE_RESULT=$(sanitize_for_workflow_command "${FIELD_RESULT}")
  echo "::error::Project 情報の取得に失敗しました: ${SAFE_RESULT}"
  echo ""
  echo "考えられる原因:"
  echo "  - PROJECT_NUMBER が正しくない"
  echo "  - PAT に Projects > Read and write 権限が付与されていない"
  echo "  - ネットワークエラー"
  exit 1
fi

# Project ID の取得
PROJECT_ID=$(echo "${FIELD_RESULT}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.id // empty")
if [[ -z "${PROJECT_ID}" ]]; then
  echo "::error::Project ID を取得できませんでした。Project #${PROJECT_NUMBER} が存在するか確認してください。"
  exit 1
fi
echo "  Project ID: ${PROJECT_ID}"

# Status フィールドの検索
STATUS_FIELD_ID=$(echo "${FIELD_RESULT}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.fields.nodes[] | select(.name == \"Status\") | .id // empty")
if [[ -z "${STATUS_FIELD_ID}" ]]; then
  echo "::error::Status フィールドが見つかりませんでした。"
  echo "::error::Project にビルトインの Status フィールドが存在するか確認してください。"
  exit 1
fi
echo "  Status Field ID: ${STATUS_FIELD_ID}"

# 現在のステータスカラムを表示
echo ""
echo "現在のステータスカラム:"
echo "${FIELD_RESULT}" | jq -r ".data.${OWNER_QUERY_FIELD}.projectV2.fields.nodes[] | select(.name == \"Status\") | .options[] | \"  - \(.name) (\(.color))\"" 2>/dev/null || echo "  （取得できませんでした）"

# --- ステータスカラムの更新 ---

echo ""
echo "テンプレート '${TEMPLATE_PATTERN}' でステータスカラムを更新します..."

STATUS_OPTIONS=$(get_status_options "${TEMPLATE_PATTERN}")

# カラム名を表示
echo ""
echo "設定するステータスカラム:"
echo "${STATUS_OPTIONS}" | jq -r '.[] | "  - \(.name) (\(.color)): \(.description)"'

# GraphQL mutation 用の singleSelectOptions を構築
SINGLE_SELECT_OPTIONS=$(echo "${STATUS_OPTIONS}" | jq -c '[.[] | {name: .name, color: .color, description: .description}]')

UPDATE_MUTATION=$(cat <<GRAPHQL
mutation {
  updateProjectV2Field(input: {
    fieldId: "${STATUS_FIELD_ID}"
    singleSelectOptions: ${SINGLE_SELECT_OPTIONS}
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField {
        id
        name
        options {
          id
          name
          color
          description
        }
      }
    }
  }
}
GRAPHQL
)

if ! UPDATE_RESULT=$(gh api graphql -f query="${UPDATE_MUTATION}" 2>&1); then
  SAFE_RESULT=$(sanitize_for_workflow_command "${UPDATE_RESULT}")
  echo "::error::ステータスカラムの更新に失敗しました: ${SAFE_RESULT}"
  echo ""
  echo "考えられる原因:"
  echo "  - PAT に Projects > Read and write 権限が付与されていない"
  echo "  - GraphQL API のレート制限に達した"
  echo "  - ネットワークエラー"
  exit 1
fi

# エラーチェック
ERRORS=$(echo "${UPDATE_RESULT}" | jq -r '.errors // empty' 2>/dev/null)
if [[ -n "${ERRORS}" && "${ERRORS}" != "null" ]]; then
  SAFE_ERRORS=$(sanitize_for_workflow_command "${ERRORS}")
  echo "::error::GraphQL エラーが発生しました: ${SAFE_ERRORS}"
  exit 1
fi

echo ""
echo "::notice::ステータスカラムの更新に成功しました。"

# 更新後のステータスカラムを表示
echo ""
echo "更新後のステータスカラム:"
echo "${UPDATE_RESULT}" | jq -r '.data.updateProjectV2Field.projectV2Field.options[] | "  - \(.name) (\(.color)): \(.description)"' 2>/dev/null || echo "  （取得できませんでした）"

# --- サマリー出力 ---

COLUMN_NAMES=$(echo "${STATUS_OPTIONS}" | jq -r '[.[].name] | join(" → ")')

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## ステータスカラム設定完了"
    echo ""
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| Project Owner | \`${PROJECT_OWNER}\` |"
    echo "| Project Number | ${PROJECT_NUMBER} |"
    echo "| Template | ${TEMPLATE_PATTERN} |"
    echo "| カラム構成 | ${COLUMN_NAMES} |"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

echo ""
echo "========================================="
echo "  完了サマリー"
echo "========================================="
echo "  Owner:    ${PROJECT_OWNER}"
echo "  Project:  #${PROJECT_NUMBER}"
echo "  Template: ${TEMPLATE_PATTERN}"
echo "  カラム:   ${COLUMN_NAMES}"
echo "========================================="
echo ""
echo "セットアップが完了しました。"
