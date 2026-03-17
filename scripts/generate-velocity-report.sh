#!/usr/bin/env bash
set -euo pipefail

# ベロシティレポート生成スクリプト
# https://mabubu0203.github.io/github-projects-starter-kit/scripts/generate-velocity-report
#
# 環境変数:
#   GH_TOKEN        - GitHub PAT（Projects 読み取り権限が必要）
#   PROJECT_OWNER   - Project の所有者
#   PROJECT_NUMBER  - 対象 Project の Number
#   ITEM_TYPE       - 対象アイテムの種別（all / issues / prs、デフォルト: all）
#   ITEM_STATE      - 対象アイテムの状態（open / closed / all、デフォルト: all）
#   OUTPUT_FORMAT   - 出力形式（json / markdown / csv / tsv、デフォルト: json）
#   VELOCITY_WEEKS  - 集計対象の週数（デフォルト: 8）

# --- 共通ライブラリ読み込み ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# --- スクリプト内定数 ---

ITEM_TYPE="${ITEM_TYPE:-all}"
ITEM_STATE="${ITEM_STATE:-all}"
VELOCITY_WEEKS="${VELOCITY_WEEKS:-8}"

# --- バリデーション ---

validate_common_project_env
validate_enum "ITEM_TYPE" "${ITEM_TYPE}" "all" "issues" "prs"
validate_enum "ITEM_STATE" "${ITEM_STATE}" "open" "closed" "all"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"
validate_enum "OUTPUT_FORMAT" "${OUTPUT_FORMAT}" "markdown" "csv" "tsv" "json"

if ! [[ "${VELOCITY_WEEKS}" =~ ^[0-9]+$ ]] || [[ "${VELOCITY_WEEKS}" -lt 1 || "${VELOCITY_WEEKS}" -gt 52 ]]; then
  echo "::error::VELOCITY_WEEKS の値が不正です: ${VELOCITY_WEEKS}（1〜52 の範囲で指定してください）"
  exit 1
fi

# --- アイテム取得 ---

echo ""
echo "Project #${PROJECT_NUMBER} のアイテムを取得しています..."
PROJECT_TITLE=""

VELOCITY_QUERY_TEMPLATE=$(cat <<'GRAPHQL'
query($login: String!, $number: Int!, $after: String) {
  __OWNER_FIELD__(login: $login) {
    projectV2(number: $number) {
      title
      items(first: 100, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name
                field { ... on ProjectV2FieldCommon { name } }
              }
              ... on ProjectV2ItemFieldNumberValue {
                number
                field { ... on ProjectV2FieldCommon { name } }
              }
            }
          }
          content {
            ... on Issue {
              __typename
              number
              title
              url
              state
              updatedAt
              repository { nameWithOwner }
              assignees(first: 100) { nodes { login } }
            }
            ... on PullRequest {
              __typename
              number
              title
              url
              state
              updatedAt
              repository { nameWithOwner }
              assignees(first: 100) { nodes { login } }
            }
          }
        }
      }
    }
  }
}
GRAPHQL
)

VELOCITY_NORMALIZE_FILTER='[.data.[($owner)].projectV2.items.nodes[]
  | select(.content != null)
  | select(.content.__typename != null)
  | {
      type:          .content.__typename,
      number:        .content.number,
      title:         .content.title,
      url:           .content.url,
      state:         .content.state,
      repository:    .content.repository.nameWithOwner,
      assignees:     [.content.assignees.nodes[].login],
      updated_at:    .content.updatedAt,
      status:        ([.fieldValues.nodes[] | select(.field.name == "Status") | .name] | first // null),
      actual_hours:  ([.fieldValues.nodes[] | select(.field.name == "実績工数(h)") | .number] | first // null)
    }]'

ITEMS=$(fetch_all_project_items "${VELOCITY_QUERY_TEMPLATE}" "${VELOCITY_NORMALIZE_FILTER}" 50)

TOTAL_BEFORE_FILTER=$(echo "${ITEMS}" | jq 'length')
echo "  合計: ${TOTAL_BEFORE_FILTER} 件（フィルタ前）"

# --- フィルタリング ---

ITEMS=$(echo "${ITEMS}" | filter_items_by_type)
ITEMS=$(echo "${ITEMS}" | filter_items_by_state)

TOTAL_COUNT=$(echo "${ITEMS}" | jq 'length')
echo "  合計: ${TOTAL_COUNT} 件（フィルタ後）"

# --- Done アイテムの抽出と集計期間の計算 ---

echo ""
echo "ベロシティ集計を実行しています..."

EXECUTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 集計期間の開始日を計算（現在の ISO 週の月曜日から VELOCITY_WEEKS 週前）
# macOS と Linux の date 互換性のため jq で計算
read -r PERIOD_START PERIOD_END < <(jq -n \
  --argjson weeks "${VELOCITY_WEEKS}" '
  now | floor |
  # 現在の曜日（月=0, 日=6）
  (. / 86400 + 3) % 7 | floor |
  # 今週の月曜日（epoch秒）
  (now | floor) - . * 86400 |
  # 今週の日曜日
  . + 6 * 86400 |
  # 集計期間の開始（VELOCITY_WEEKS 週前の月曜日）
  [(. - 6 * 86400 - ($weeks - 1) * 7 * 86400 | strftime("%Y-%m-%d")),
   (. | strftime("%Y-%m-%d"))] | @tsv
' | tr '\t' ' ')

echo "  集計期間: ${PERIOD_START} 〜 ${PERIOD_END}（${VELOCITY_WEEKS} 週間）"

# Done ステータスのアイテムを抽出し、集計期間内のものに絞り込み
DONE_ITEMS=$(echo "${ITEMS}" | jq --arg start "${PERIOD_START}" --arg end "${PERIOD_END}" '
  [.[] |
    select(.status == "Done") |
    (.updated_at | split("T")[0]) as $date |
    select($date >= $start and $date <= $end)
  ]
')

DONE_COUNT=$(echo "${DONE_ITEMS}" | jq 'length')
echo "  Done アイテム数（期間内）: ${DONE_COUNT} 件"

# --- 週別ベロシティ集計 ---

# ISO 週ラベルと期間で集計
WEEKLY_VELOCITY=$(echo "${DONE_ITEMS}" | jq --arg start "${PERIOD_START}" --argjson weeks "${VELOCITY_WEEKS}" '
  # 集計期間の各週の情報を生成
  [range($weeks)] |
  map(
    . as $i |
    ($start | strptime("%Y-%m-%d") | mktime + $i * 7 * 86400) as $week_start |
    ($week_start + 6 * 86400) as $week_end |
    ($week_start | strftime("%Y-%m-%d")) as $ws |
    ($week_end | strftime("%Y-%m-%d")) as $we |
    ($week_start | strftime("W%V")) as $week_label |
    ($ws | split("-") | .[1:] | join("/")) as $ws_short |
    ($we | split("-") | .[1:] | join("/")) as $we_short |
    {
      week_label: $week_label,
      week_start: $ws,
      week_end: $we,
      period_display: ($ws_short + "\u301c" + $we_short)
    }
  ) |
  # 各週にマッチするアイテムを集計
  . as $weeks_info |
  $weeks_info | map(
    . as $week |
    ($ARGS.positional[0] // []) as $items |
    ($items | [.[] |
      select(
        (.updated_at | split("T")[0]) >= $week.week_start
        and (.updated_at | split("T")[0]) <= $week.week_end
      )
    ]) as $week_items |
    $week + {
      count: ($week_items | length),
      actual_hours: ([$week_items[].actual_hours // 0] | add // 0)
    }
  )
' --jsonargs "${DONE_ITEMS}")

# 工数データの有無を判定
HAS_HOURS=$(echo "${DONE_ITEMS}" | jq '[.[] | select(.actual_hours != null and .actual_hours > 0)] | length > 0')

# 平均ベロシティ
AVG_COUNT=$(echo "${WEEKLY_VELOCITY}" | jq --argjson weeks "${VELOCITY_WEEKS}" '
  ([.[].count] | add // 0) / $weeks * 10 | round / 10
')

AVG_HOURS="0"
if [[ "${HAS_HOURS}" == "true" ]]; then
  AVG_HOURS=$(echo "${WEEKLY_VELOCITY}" | jq --argjson weeks "${VELOCITY_WEEKS}" '
    ([.[].actual_hours] | add // 0) / $weeks * 10 | round / 10
  ')
fi

echo "  平均ベロシティ: ${AVG_COUNT} 件/週"
if [[ "${HAS_HOURS}" == "true" ]]; then
  echo "  平均完了工数: ${AVG_HOURS} h/週"
fi

# --- 担当者別ベロシティ ---

ASSIGNEE_VELOCITY=$(echo "${DONE_ITEMS}" | jq '
  [.[] | . as $item |
    (if (.assignees | length) == 0 then ["(未アサイン)"] else .assignees end)[] |
    {
      assignee: .,
      actual_hours: $item.actual_hours
    }
  ]
  | sort_by(.assignee) | group_by(.assignee)
  | map({
      assignee: .[0].assignee,
      count: length,
      actual_hours: ([.[].actual_hours // 0] | add)
    })
  | sort_by(-.count)
')

echo "  担当者別: $(echo "${ASSIGNEE_VELOCITY}" | jq 'length') 件"

# --- フォーマッター関数 ---

format_velocity_markdown() {
  {
    echo "# ベロシティレポート"
    echo ""
    echo "- **Project:** ${PROJECT_TITLE} (#${PROJECT_NUMBER})"
    echo "- **実行日時:** ${EXECUTED_AT}"
    echo "- **集計期間:** ${PERIOD_START} 〜 ${PERIOD_END}（${VELOCITY_WEEKS} 週間）"
    echo "- **Done アイテム数:** ${DONE_COUNT} 件"
    echo "- **平均ベロシティ:** ${AVG_COUNT} 件/週"
    if [[ "${HAS_HOURS}" == "true" ]]; then
      echo "- **平均完了工数:** ${AVG_HOURS} h/週"
    fi
    echo ""
    echo "---"
    echo ""

    # 週別ベロシティ
    echo "## 週別ベロシティ"
    echo ""
    if [[ "${HAS_HOURS}" == "true" ]]; then
      echo "| 週 | 期間 | 完了数 | 完了工数(h) |"
      echo "|---|---|---|---|"
      echo "${WEEKLY_VELOCITY}" | jq -r '.[] | "| \(.week_label) | \(.period_display) | \(.count) | \(.actual_hours) |"'
    else
      echo "| 週 | 期間 | 完了数 |"
      echo "|---|---|---|"
      echo "${WEEKLY_VELOCITY}" | jq -r '.[] | "| \(.week_label) | \(.period_display) | \(.count) |"'
    fi
    echo ""

    # Mermaid チャート（完了数）
    local has_nonzero
    has_nonzero=$(echo "${WEEKLY_VELOCITY}" | jq '[.[] | select(.count > 0)] | length')
    if [[ "${has_nonzero}" -gt 0 ]]; then
      echo '```mermaid'
      echo 'xychart-beta'
      echo '    title "週別完了アイテム数"'
      echo -n '    x-axis ['
      echo "${WEEKLY_VELOCITY}" | jq -r '[.[] | "\"\(.week_label)\""] | join(", ")' | tr -d '\n'
      echo ']'
      echo -n '    y-axis "完了数" 0 --> '
      echo "${WEEKLY_VELOCITY}" | jq '[.[].count] | max + 2'
      echo -n '    bar ['
      echo "${WEEKLY_VELOCITY}" | jq -r '[.[].count | tostring] | join(", ")' | tr -d '\n'
      echo ']'
      echo '```'
      echo ""
    fi

    # Mermaid チャート（完了工数）
    if [[ "${HAS_HOURS}" == "true" ]]; then
      local has_nonzero_hours
      has_nonzero_hours=$(echo "${WEEKLY_VELOCITY}" | jq '[.[] | select(.actual_hours > 0)] | length')
      if [[ "${has_nonzero_hours}" -gt 0 ]]; then
        echo '```mermaid'
        echo 'xychart-beta'
        echo '    title "週別完了工数(h)"'
        echo -n '    x-axis ['
        echo "${WEEKLY_VELOCITY}" | jq -r '[.[] | "\"\(.week_label)\""] | join(", ")' | tr -d '\n'
        echo ']'
        echo -n '    y-axis "工数(h)" 0 --> '
        echo "${WEEKLY_VELOCITY}" | jq '[.[].actual_hours] | max + 5 | floor'
        echo -n '    bar ['
        echo "${WEEKLY_VELOCITY}" | jq -r '[.[].actual_hours | tostring] | join(", ")' | tr -d '\n'
        echo ']'
        echo '```'
        echo ""
      fi
    fi

    # 担当者別ベロシティ
    local assignee_count
    assignee_count=$(echo "${ASSIGNEE_VELOCITY}" | jq 'length')
    if [[ "${assignee_count}" -gt 0 ]]; then
      echo "## 担当者別ベロシティ（集計期間合計）"
      echo ""
      if [[ "${HAS_HOURS}" == "true" ]]; then
        echo "| 担当者 | 完了数 | 完了工数(h) |"
        echo "|---|---|---|"
        echo "${ASSIGNEE_VELOCITY}" | jq -r '.[] | "| \(.assignee) | \(.count) | \(.actual_hours) |"'
      else
        echo "| 担当者 | 完了数 |"
        echo "|---|---|"
        echo "${ASSIGNEE_VELOCITY}" | jq -r '.[] | "| \(.assignee) | \(.count) |"'
      fi
      echo ""

      # Mermaid 円グラフ
      local has_assignee_data
      has_assignee_data=$(echo "${ASSIGNEE_VELOCITY}" | jq '[.[] | select(.count > 0)] | length')
      if [[ "${has_assignee_data}" -gt 0 ]]; then
        echo '```mermaid'
        echo 'pie title 担当者別完了数'
        echo "${ASSIGNEE_VELOCITY}" | jq -r '.[] | select(.count > 0) | "    \"\(.assignee)\" : \(.count)"'
        echo '```'
        echo ""
      fi
    fi
  }
}

format_velocity_csv() {
  echo "week_label,week_start,week_end,count,actual_hours"
  echo "${WEEKLY_VELOCITY}" | jq -r '.[] | [.week_label, .week_start, .week_end, .count, .actual_hours] | @csv'
}

format_velocity_tsv() {
  echo -e "week_label\tweek_start\tweek_end\tcount\tactual_hours"
  echo "${WEEKLY_VELOCITY}" | jq -r '.[] | [.week_label, .week_start, .week_end, (.count | tostring), (.actual_hours | tostring)] | @tsv'
}

# --- レポート出力 ---

echo ""
echo "レポートを生成しています..."

FILE_EXT=$(get_file_extension "${OUTPUT_FORMAT}")
OUTPUT_FILE="report-${PROJECT_NUMBER}-velocity.${FILE_EXT}"

case "${OUTPUT_FORMAT}" in
  json)
    REPORT_JSON=$(jq -n \
      --arg project_title "${PROJECT_TITLE}" \
      --argjson project_number "${PROJECT_NUMBER}" \
      --arg executed_at "${EXECUTED_AT}" \
      --arg period_start "${PERIOD_START}" \
      --arg period_end "${PERIOD_END}" \
      --argjson velocity_weeks "${VELOCITY_WEEKS}" \
      --argjson done_count "${DONE_COUNT}" \
      --argjson avg_count "${AVG_COUNT}" \
      --argjson avg_hours "${AVG_HOURS}" \
      --argjson has_hours "${HAS_HOURS}" \
      --argjson weekly "${WEEKLY_VELOCITY}" \
      --argjson by_assignee "${ASSIGNEE_VELOCITY}" '
      {
        project: {
          title: $project_title,
          number: $project_number
        },
        executed_at: $executed_at,
        period: {
          start: $period_start,
          end: $period_end,
          weeks: $velocity_weeks
        },
        overview: {
          done_count: $done_count,
          avg_count_per_week: $avg_count,
          avg_hours_per_week: (if $has_hours then $avg_hours else null end)
        },
        weekly_velocity: $weekly,
        by_assignee: $by_assignee
      }
    ')
    echo "${REPORT_JSON}" > "${OUTPUT_FILE}"
    ;;
  markdown)
    format_velocity_markdown > "${OUTPUT_FILE}"
    ;;
  csv)
    format_velocity_csv > "${OUTPUT_FILE}"
    ;;
  tsv)
    format_velocity_tsv > "${OUTPUT_FILE}"
    ;;
esac

echo "  出力: ${OUTPUT_FILE}（形式: ${OUTPUT_FORMAT}）"

# --- Workflow Summary 出力 ---

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  format_velocity_markdown >> "${GITHUB_STEP_SUMMARY}"
fi

# --- コンソールサマリー ---

print_summary "Project" "${PROJECT_TITLE} (#${PROJECT_NUMBER})" \
  "形式" "${OUTPUT_FORMAT}" \
  "集計期間" "${PERIOD_START} 〜 ${PERIOD_END}" \
  "週数" "${VELOCITY_WEEKS} 週間" \
  "Done 件数" "${DONE_COUNT} 件" \
  "平均" "${AVG_COUNT} 件/週" \
  "出力先" "${OUTPUT_FILE}"

echo ""
echo "::notice::ベロシティレポートの生成が完了しました（Done: ${DONE_COUNT} 件、${VELOCITY_WEEKS} 週間）。"
