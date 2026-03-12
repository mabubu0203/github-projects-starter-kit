# add-items-to-project.sh

リポジトリの Issue/PR を Project に一括追加するスクリプトです。
既に Project に追加済みのアイテムは自動的にスキップされます。

## 環境変数

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |
| `TARGET_REPO` | 対象リポジトリ（owner/repo 形式） | ✅ |
| `INCLUDE_ISSUES` | Issue を追加対象にする（`true`/`false`） | ❌（デフォルト: `true`） |
| `INCLUDE_PRS` | PR を追加対象にする（`true`/`false`） | ❌（デフォルト: `true`） |
| `ITEM_STATE` | 取得するアイテムの状態（`open`/`closed`/`all`） | ❌（デフォルト: `open`） |
| `ITEM_LABEL` | 絞り込みラベル | ❌ |

## 処理フロー

```mermaid
flowchart TD
    A["開始"] --> B["環境変数バリデーション"]
    B --> C["オーナータイプ判定"]
    C --> D["GraphQL で Project の\n既存アイテム URL 一覧を取得\n（ページネーション対応）"]

    D --> E{"INCLUDE_ISSUES = true?"}
    E -- "Yes" --> F["gh issue list で\nIssue URL 一覧を取得"]
    F --> G["各 Issue をループ"]
    G --> H{"既存アイテムに\n含まれる?"}
    H -- "Yes" --> I["スキップ"]
    H -- "No" --> J["gh project item-add\nで追加"]
    I & J --> K{"次の Issue\nあり?"}
    K -- "Yes" --> G
    K -- "No" --> L{"INCLUDE_PRS = true?"}

    E -- "No" --> L

    L -- "Yes" --> M["gh pr list で\nPR URL 一覧を取得"]
    M --> N["各 PR をループ"]
    N --> O{"既存アイテムに\n含まれる?"}
    O -- "Yes" --> P["スキップ"]
    O -- "No" --> Q["gh project item-add\nで追加"]
    P & Q --> R{"次の PR\nあり?"}
    R -- "Yes" --> N
    R -- "No" --> S["サマリー出力"]

    L -- "No" --> S
    S --> T["完了"]
```

## 処理詳細

| ステップ | 処理内容 | 使用コマンド / API |
|---------|---------|-------------------|
| オーナータイプ判定 | `detect_owner_type` で Organization / User を判別 | `gh api users/{owner}` |
| 既存アイテム取得 | GraphQL クエリで Project に紐づく全アイテムの URL をページネーション付きで取得。重複防止に使用 | `gh api graphql` — `projectV2.items(first: 100)` |
| Issue 取得 | `ITEM_STATE`・`ITEM_LABEL` で絞り込んで Issue 一覧を取得（最大 500 件） | `gh issue list --repo --state --limit 500 --json url` |
| PR 取得 | Issue と同様のフィルタで PR 一覧を取得 | `gh pr list --repo --state --limit 500 --json url` |
| 重複チェック | 既存アイテム URL リストと各 Issue/PR の URL を `grep -Fxq` で完全一致比較 | — |
| アイテム追加 | 重複していない各 Issue/PR を Project に追加（1件ごとに 1秒の sleep を挟みレート制限を回避） | `gh project item-add {number} --owner --url` |
| サマリー出力 | Issue・PR それぞれの追加・スキップ・失敗件数をコンソールと `GITHUB_STEP_SUMMARY` に出力 | — |

## API リファレンス

| API / コマンド | 用途 | リファレンス |
|---------------|------|-------------|
| `projectV2.items` (GraphQL) | 既存アイテム URL の取得（重複防止） | [ProjectV2](https://docs.github.com/en/graphql/reference/objects#projectv2) |
| `gh issue list` | Issue 一覧の取得 | [gh issue list](https://cli.github.com/manual/gh_issue_list) |
| `gh pr list` | PR 一覧の取得 | [gh pr list](https://cli.github.com/manual/gh_pr_list) |
| `gh project item-add` | アイテムの Project への追加 | [gh project item-add](https://cli.github.com/manual/gh_project_item-add) |

### パラメータ上限

| パラメータ | 現在の値 | 備考 |
|-----------|---------|------|
| `items(first: N)` | 100 | 既存アイテム取得のページサイズ |
| `--limit` | 500 | `gh issue list` / `gh pr list` の最大取得件数 |
| `sleep` | 1秒 | アイテム追加間のレート制限回避待機時間 |

## 使用ワークフロー

- [③ Issue/PR 一括紐付け](../03-add-items-to-project)
