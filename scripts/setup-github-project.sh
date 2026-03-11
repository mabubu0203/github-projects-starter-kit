#!/usr/bin/env bash
set -euo pipefail

# GitHub Project セットアップスクリプト
# 環境変数:
#   GH_TOKEN       - GitHub PAT（Projects 操作権限が必要）
#   PROJECT_OWNER  - Project を作成する Owner
#   PROJECT_TITLE  - 作成する Project のタイトル

# --- バリデーション ---

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::GH_TOKEN が設定されていません。Secrets に PROJECT_PAT を設定してください。"
  exit 1
fi

if [[ -z "${PROJECT_OWNER:-}" ]]; then
  echo "::error::PROJECT_OWNER が指定されていません。"
  exit 1
fi

if [[ -z "${PROJECT_TITLE:-}" ]]; then
  echo "::error::PROJECT_TITLE が指定されていません。"
  exit 1
fi

# --- Project 作成 ---

echo "GitHub Project を作成します..."
echo "  Owner: ${PROJECT_OWNER}"
echo "  Title: ${PROJECT_TITLE}"

if ! OUTPUT=$(gh project create --title "${PROJECT_TITLE}" --owner "${PROJECT_OWNER}" --format json 2>&1); then
  echo "::error::GitHub Project の作成に失敗しました。"
  echo "::error::詳細: ${OUTPUT}"
  echo ""
  echo "考えられる原因:"
  echo "  - PAT に必要な権限（project スコープ）が付与されていない"
  echo "  - Owner 名が正しくない"
  echo "  - ネットワークエラー"
  exit 1
fi

echo "::notice::GitHub Project の作成に成功しました。"
echo "${OUTPUT}" | jq '.' 2>/dev/null || echo "${OUTPUT}"

# Project URL をサマリーに出力
if command -v jq &>/dev/null; then
  PROJECT_URL=$(echo "${OUTPUT}" | jq -r '.url // empty')
  PROJECT_NUMBER=$(echo "${OUTPUT}" | jq -r '.number // empty')

  if [[ -n "${PROJECT_URL}" ]]; then
    echo ""
    echo "Project URL: ${PROJECT_URL}"
    echo "Project Number: ${PROJECT_NUMBER}"

    # GitHub Actions のサマリーに出力
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      {
        echo "## GitHub Project 作成完了"
        echo ""
        echo "| 項目 | 値 |"
        echo "|------|-----|"
        echo "| Owner | \`${PROJECT_OWNER}\` |"
        echo "| Title | ${PROJECT_TITLE} |"
        echo "| Number | ${PROJECT_NUMBER} |"
        echo "| URL | ${PROJECT_URL} |"
      } >> "${GITHUB_STEP_SUMMARY}"
    fi
  fi
fi

echo ""
echo "セットアップが完了しました。"
