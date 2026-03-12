# create-project-views.sh

Project に View を自動作成するスクリプトです。
既に同名の View が存在する場合は自動的にスキップされます。

## 環境変数

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |

## 作成される View

- `Table`（TABLE_LAYOUT）
- `Board`（BOARD_LAYOUT）
- `Roadmap`（ROADMAP_LAYOUT）

## 処理フロー

```mermaid
flowchart TD
    A["開始"] --> B["環境変数バリデーション"]
    B --> C["オーナータイプ判定"]
    C --> D["GraphQL で既存 View 一覧を取得\n（ページネーション対応）"]
    D --> E{"取得成功?"}
    E -- "No" --> F["エラー出力"]
    F --> G["異常終了"]

    E -- "Yes" --> H["View 定義をループ\n（Table / Board / Roadmap）"]
    H --> I{"同名 View\n既に存在?"}
    I -- "Yes" --> J["スキップ"]
    I -- "No" --> K["GraphQL mutation で\nView を作成"]
    K --> L{"作成成功?"}
    L -- "Yes" --> M["作成カウント +1"]
    L -- "No" --> N["失敗カウント +1"]

    J & M & N --> O{"次の View\nあり?"}
    O -- "Yes" --> H
    O -- "No" --> P["サマリー出力"]
    P --> Q{"失敗あり?"}
    Q -- "Yes" --> G
    Q -- "No" --> R["完了"]
```

## 処理詳細

| ステップ | 処理内容 | 使用コマンド / API |
|---------|---------|-------------------|
| オーナータイプ判定 | `detect_owner_type` で Organization / User を判別 | `gh api users/{owner}` |
| 既存 View 取得 | GraphQL クエリで Project の全 View（名前・レイアウト）をページネーション付きで取得（100件ずつ） | `gh api graphql` — `projectV2.views(first: 100)` |
| 重複チェック | 既存 View 名リストと定義済み View 名を `grep -Fqx` で完全一致比較 | — |
| View 作成 | GraphQL mutation で View を作成。GraphQL 変数（`$projectId`・`$name`・`$layout`）を使用して安全に値を渡す | `gh api graphql` — `createProjectV2View` mutation |
| サマリー出力 | 作成・スキップ・失敗の件数をコンソールと `GITHUB_STEP_SUMMARY` に出力 | — |

## API リファレンス

| API / コマンド | 用途 | リファレンス |
|---------------|------|-------------|
| `projectV2.views` (GraphQL) | 既存 View 一覧の取得 | [ProjectV2](https://docs.github.com/en/graphql/reference/objects#projectv2) |
| `createProjectV2View` (GraphQL Mutation) | View の作成 | [createProjectV2View](https://docs.github.com/en/graphql/reference/mutations#createprojectv2view) |
| `ProjectV2ViewLayout` (GraphQL Enum) | View レイアウト種別 | [ProjectV2ViewLayout](https://docs.github.com/en/graphql/reference/enums#projectv2viewlayout) |

### パラメータ上限

| パラメータ | 現在の値 | 備考 |
|-----------|---------|------|
| `views(first: N)` | 100 | View のページサイズ（ページネーション対応） |

## 使用ワークフロー

- [① GitHub Project 新規作成](../01-create-project)
- [② GitHub Project 拡張](../02-extend-project)
