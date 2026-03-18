# Issue #33: GitHub Project の Issue/PR 一覧エクスポート機能

## Context

GitHub Projects の初期セットアップ自動化の次段階として、作成済み Project に紐づく Issue/PR 一覧を取得し、外部共有や確認用にエクスポートできるようにする。4つの出力形式（markdown, csv, tsv, json）に対応し、GitHub Actions から手動実行可能な workflow を追加する。

## 作成ファイル一覧

| ファイル | 種別 | 概要 |
|---------|------|------|
| `.github/workflows/04-export-project-items.yml` | 新規 | workflow_dispatch で手動実行する workflow |
| `scripts/export-project-items.sh` | 新規 | エクスポート処理のメインスクリプト |
| `docs/04-export-project-items.md` | 新規 | ドキュメントページ |
| `docs/scripts/export-project-items.md` | 新規 | スクリプト詳細ドキュメント |
| `docs/index.md` | 更新 | ④ のリンク追加 |

**既存ファイルの変更は `docs/index.md` のみ。** `scripts/lib/common.sh` は変更不要（必要なユーティリティは全て揃っている）。

---

## 1. Workflow: `04-export-project-items.yml`

```yaml
name: "④ Project アイテム エクスポート"
on:
  workflow_dispatch:
    inputs:
      project_number:
        description: "対象 Project の Number"
        required: true
        type: string
      output_format:
        description: "出力形式"
        required: true
        type: choice
        options: [markdown, csv, tsv, json]
        default: "markdown"
permissions:
  contents: read
jobs:
  export-items:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.PROJECT_PAT }}
      PROJECT_OWNER: ${{ github.repository_owner }}
      PROJECT_NUMBER: ${{ inputs.project_number }}
    steps:
      - uses: actions/checkout@v6.0.2
      - name: Project アイテムをエクスポート
        env:
          OUTPUT_FORMAT: ${{ inputs.output_format }}
        run: |
          chmod +x scripts/export-project-items.sh
          bash scripts/export-project-items.sh
      - name: アーティファクトをアップロード
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: project-items-export
          path: export-*
          if-no-files-found: ignore
          retention-days: 30
```

**設計判断:**
- `owner_type` 入力は不要 → `detect_owner_type()` で自動判定（`add-items-to-project.sh` と同じ方式）
- artifact は `if: always()` で部分結果もキャプチャ
- `if-no-files-found: ignore` でファイル未生成時もエラーにしない

---

## 2. スクリプト: `scripts/export-project-items.sh`

### 構造

```
#!/usr/bin/env bash
set -euo pipefail

# ヘッダー（purpose, GitHub Pages link, 環境変数）
# 共通ライブラリ読み込み
# バリデーション
# オーナータイプ判定
# アイテム取得（ページネーション）
# データ正規化（DraftIssue 除外）
# フォーマッター関数（4種類）
# ファイル出力
# Step Summary 出力
# コンソールサマリー
```

### 環境変数

| 変数 | 必須 | 説明 |
|------|:----:|------|
| `GH_TOKEN` | ✅ | GitHub PAT |
| `PROJECT_OWNER` | ✅ | Project の所有者 |
| `PROJECT_NUMBER` | ✅ | 対象 Project の Number |
| `OUTPUT_FORMAT` | - | 出力形式（デフォルト: markdown） |

### GraphQL クエリ

`add-items-to-project.sh` の `get_existing_project_items()` をベースに、取得フィールドを拡張する:

```graphql
query {
  ${OWNER_QUERY_FIELD}(login: "${PROJECT_OWNER}") {
    projectV2(number: ${PROJECT_NUMBER}) {
      title
      items(first: 100, after: "${cursor}") {
        pageInfo { hasNextPage, endCursor }
        nodes {
          content {
            ... on Issue {
              __typename
              number, title, url, state
              createdAt, updatedAt
              author { login }
              repository { nameWithOwner }
              assignees(first: 10) { nodes { login } }
              labels(first: 10) { nodes { name } }
            }
            ... on PullRequest {
              __typename
              number, title, url, state
              createdAt, updatedAt
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
```

- `__typename` で Issue / PullRequest を判別
- DraftIssue は GraphQL fragment に含めない → content が null の item はスキップ
- ページネーション: `hasNextPage` / `endCursor` パターン（上限50ページ = 5000件）

### データ正規化

jq で各 node を以下のフラット構造に変換:

```json
{
  "type": "Issue",
  "number": 42,
  "title": "タイトル",
  "url": "https://...",
  "state": "OPEN",
  "repository": "owner/repo",
  "author": "username",
  "assignees": "user1, user2",
  "labels": "bug, enhancement",
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-02T00:00:00Z"
}
```

- `content` が null の item（DraftIssue 等）はスキップ
- `__typename` が `PullRequest` → type = "PullRequest"、それ以外 → type = "Issue"
- assignees/labels は `, ` 区切りの文字列に結合

### フォーマッター関数

| 関数 | 処理 |
|------|------|
| `format_markdown()` | Markdown テーブル。`\|` エスケープ。Issue/PR をセクション分け |
| `format_csv()` | `jq @csv` で出力。ヘッダー行あり |
| `format_tsv()` | `jq @tsv` で出力。ヘッダー行あり |
| `format_json()` | `jq '.'` でプリティプリント |

### ファイル出力

- ファイル名: `export-${PROJECT_NUMBER}-items.{md|csv|tsv|json}`
- ワークスペースルートに出力

### Step Summary 出力

- サマリーテーブル（Project 情報、件数）
- markdown 形式: エクスポート結果をそのまま埋め込み（100行超は切り詰め）
- csv/tsv/json 形式: 先頭20行のプレビュー（コードブロック）+ artifact ダウンロード案内

### エラーハンドリング

- GraphQL エラー: `.errors` チェック → `::error::` + exit 1
- 0件: `::warning::` + 空ファイル出力（ヘッダーのみ / 空配列）→ exit 0
- ページネーション安全弁: 50ページ上限 + `::warning::` メッセージ

---

## 3. ドキュメント

### `docs/04-export-project-items.md`

`03-add-items-to-project.md` と同じ構成:
- 使い方（Actions タブ → 選択 → パラメータ入力 → 実行）
- パラメータテーブル
- ワークフロー構成図
- スクリプト詳細リンク

### `docs/scripts/export-project-items.md`

スクリプトの詳細ドキュメント。

### `docs/index.md` 更新

ワークフロー一覧テーブルと構成ファイルツリーに ④ を追加。

---

## 4. 独立サブタスク分析

以下の2つは独立して実装可能:
1. **スクリプト + Workflow**: `export-project-items.sh` + `04-export-project-items.yml`
2. **ドキュメント**: `docs/04-export-project-items.md` + `docs/scripts/export-project-items.md` + `docs/index.md` 更新

---

## 5. コミット計画

| # | メッセージ | 対象ファイル |
|---|-----------|-------------|
| 1 | `feat: GitHub Project アイテムエクスポート機能を追加 (#33)` | `scripts/export-project-items.sh`, `.github/workflows/04-export-project-items.yml` |
| 2 | `docs: エクスポート機能のドキュメントを追加 (#33)` | `docs/04-export-project-items.md`, `docs/scripts/export-project-items.md`, `docs/index.md` |

---

## 6. 検証方法

- `shellcheck scripts/export-project-items.sh` で静的解析
- `bash -n scripts/export-project-items.sh` で構文チェック
- ローカル実行テスト（`GITHUB_STEP_SUMMARY` 未設定でもエラーにならないことを確認）
- workflow YAML の構文確認（`actionlint` があれば使用）
