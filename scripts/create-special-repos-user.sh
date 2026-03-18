#!/usr/bin/env bash
set -euo pipefail

# 個人アカウント用の特殊Repository一括作成スクリプト
# https://mabubu0203.github.io/github-projects-starter-kit/scripts/create-special-repos-user
#
# 環境変数:
#   GH_TOKEN      - GitHub PAT（repo スコープまたは Administration: write が必要）
#   PROJECT_OWNER - 対象の個人アカウント名

# --- 共通ライブラリ読み込み ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- バリデーション ---

require_env "GH_TOKEN" "Secrets に PROJECT_PAT を設定してください。"
require_env "PROJECT_OWNER"
require_command "gh" "GitHub CLI (gh) が必要です。PATH を確認してください。"
require_command "jq" "JSON の解析に必要です。"

# --- オーナータイプ判定 ---

detect_owner_type

if [[ "${OWNER_TYPE}" != "User" ]]; then
  echo "::error::PROJECT_OWNER（${PROJECT_OWNER}）は個人アカウントではありません（タイプ: ${OWNER_TYPE}）。Organization の場合は create-special-repos-org.sh を使用してください。"
  exit 1
fi

# --- Repository定義ファイルの読み込み ---

REPO_DEFINITIONS_FILE="${SCRIPT_DIR}/config/special-repo-definitions-user.json"
if [[ ! -f "${REPO_DEFINITIONS_FILE}" ]]; then
  echo "::error::Repository定義ファイルが見つかりません: ${REPO_DEFINITIONS_FILE}"
  exit 1
fi

REPO_DEFINITIONS=$(cat "${REPO_DEFINITIONS_FILE}")
REPO_COUNT=$(echo "${REPO_DEFINITIONS}" | jq 'length')

echo ""
echo "個人アカウント用の特殊Repositoryを作成します..."
echo "  オーナー: ${PROJECT_OWNER}"
echo "  定義数: ${REPO_COUNT} 件"

if [[ "${REPO_COUNT}" -eq 0 ]]; then
  echo ""
  echo "Repository定義が空のため、処理をスキップします。"
  print_summary "Owner" "${PROJECT_OWNER}" "作成" "0 件" "スキップ" "0 件" "失敗" "0 件"
  exit 0
fi

# --- Repositoryの一括作成 ---

PARSED_REPOS=$(echo "${REPO_DEFINITIONS}" | jq -r --arg owner "${PROJECT_OWNER}" \
  '.[] | [(.name_template | gsub("\\{\\{owner\\}\\}"; $owner)), .description, .visibility, (.auto_init | tostring)] | @tsv')

CREATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0
REPO_INDEX=0

while IFS=$'\t' read -r REPO_NAME REPO_DESCRIPTION REPO_VISIBILITY REPO_AUTO_INIT; do
  REPO_INDEX=$((REPO_INDEX + 1))

  echo ""
  echo "  [${REPO_INDEX}/${REPO_COUNT}] ${PROJECT_OWNER}/${REPO_NAME} (${REPO_VISIBILITY})"

  # 既存Repositoryの重複チェック
  if gh api "repos/${PROJECT_OWNER}/${REPO_NAME}" \
    -H "X-GitHub-Api-Version: ${REST_API_VERSION}" \
    >/dev/null 2>&1; then
    echo "    → 既存Repositoryのためスキップしました。"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  # visibility を private パラメータに変換
  PRIVATE_FLAG="false"
  if [[ "${REPO_VISIBILITY}" == "private" ]]; then
    PRIVATE_FLAG="true"
  fi

  # Repository作成（POST /user/repos）
  if gh api "user/repos" \
    -H "X-GitHub-Api-Version: ${REST_API_VERSION}" \
    --method POST \
    -f name="${REPO_NAME}" \
    -f description="${REPO_DESCRIPTION}" \
    -F private="${PRIVATE_FLAG}" \
    -F auto_init="${REPO_AUTO_INIT}" \
    >/dev/null 2>&1; then
    echo "    → 作成しました。"
    CREATED_COUNT=$((CREATED_COUNT + 1))
  else
    echo "    → 作成に失敗しました。"
    SAFE_REPO_NAME=$(sanitize_for_workflow_command "${REPO_NAME}")
    echo "::error::Repository '${PROJECT_OWNER}/${SAFE_REPO_NAME}' の作成に失敗しました。"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done <<< "${PARSED_REPOS}"

# --- サマリー出力 ---

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## 個人アカウント用特殊Repository一括作成完了"
    echo ""
    echo "| 項目 | 件数 |"
    echo "|------|------|"
    echo "| 作成 | ${CREATED_COUNT} |"
    echo "| スキップ | ${SKIPPED_COUNT} |"
    echo "| 失敗 | ${FAILED_COUNT} |"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

print_summary "Owner" "${PROJECT_OWNER}" "タイプ" "User" "作成" "${CREATED_COUNT} 件" "スキップ" "${SKIPPED_COUNT} 件" "失敗" "${FAILED_COUNT} 件"

if [[ "${FAILED_COUNT}" -gt 0 ]]; then
  echo ""
  echo "::error::${FAILED_COUNT} 件のRepository作成に失敗しました。"
  exit 1
fi

echo ""
echo "セットアップが完了しました。"
