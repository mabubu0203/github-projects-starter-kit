# export-project-items.sh

指定した GitHub Project に紐づく Issue / Pull Request の一覧を取得し、エクスポートするスクリプトです。
DraftIssue は出力対象外となります。

## 環境変数

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 読み取り権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |
| `OUTPUT_FORMAT` | 出力形式（`markdown`/`csv`/`tsv`/`json`） | ❌（デフォルト: `markdown`） |

## 使用ワークフロー

- [④ Project アイテム エクスポート](../04-export-project-items)
