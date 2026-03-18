# Issue #5: GitHub Projectのカスタムフィールド・ステータス初期セットアップ機能の調査

## Context

Issue #1で作成したGitHub Projectセットアップワークフローの拡張として、カスタムフィールドやステータスの初期設定を自動化する機能を検討する。本Issueのゴールは**コード実装ではなく、調査・まとめ・実装Issue起票**。

## 作業手順

### Step 1: ブランチ準備
- `main`にチェックアウト・pull
- `issues/#5`ブランチを作成・チェックアウト

### Step 2: 調査結果をIssueコメントとして投稿
`gh issue comment 5`で以下の調査結果をまとめて投稿:

**A. `gh project create`の追加引数**
- `--title`, `--owner`, `--format`のみ。カスタムフィールド一括指定は不可
- Project作成後に`gh project field-create`/`edit`/`item-add`等で構成する必要あり

**B. 関連CLIコマンド**
- `gh project field-create`: --name, --data-type (TEXT|SINGLE_SELECT|DATE|NUMBER), --single-select-options
- `gh project edit`: --title, --description, --readme, --visibility
- `gh project item-add`: --url でIssue/PRを追加
- ビルトインStatusフィールドはCLIから直接操作不可（GraphQL API経由）

**C. オーソドックスなカスタムフィールド**

| フィールド名 | データ型 | 目的 |
|---|---|---|
| Priority | SINGLE_SELECT (P0-P3) | トリアージ・優先度の可視化 |
| Estimate/Size | SINGLE_SELECT (XS-XL) or NUMBER | スプリントプランニング・ベロシティ計測 |
| Sprint/Iteration | TEXT or SINGLE_SELECT | タイムボックス管理 |
| Category/Type | SINGLE_SELECT (Bug/Feature/Chore) | 作業種別分類 |
| Due Date | DATE | 期限管理 |

**D. ステータスカラムの典型パターン**
- Kanban: Backlog → Todo → In Progress → In Review → Done
- Sprint Board: Sprint Backlog → In Progress → In Review → Done → Blocked
- シンプル: Todo → In Progress → Done

### Step 3: 実装Issueの起票（5件）

1. **カスタムフィールド自動作成機能**
   - `gh project field-create`でフィールドを作成するスクリプト・ワークフロー追加
   - 入力: PROJECT_NUMBER, PROJECT_OWNER, フィールド定義

2. **ステータスカラム初期設定機能**
   - ビルトインStatusフィールドの設定（GraphQL API経由）
   - SINGLE_SELECTでの代替アプローチも検討

3. **リポジトリのIssue/PRをProjectに追加する機能**
   - `gh project item-add`で一括追加するスクリプト
   - レート制限対策、重複防止

4. **テンプレート対応（Kanban / Sprint Board等）**
   - フィールド定義のプリセットをJSONで管理
   - Issue 1, 2の完了が前提

5. **個人アカウント / Organization の分岐処理改善**
   - `gh api users/{owner}`でUser/Org自動判定
   - 既存`setup-github-project.sh`の修正

### Step 4: 実行計画をIssueコメントとして投稿
Step 2の前に、実行計画の概要をIssue #5にコメント

### Step 5: コミット・PR
- 本Issueでは新規コードの追加はないため、PRは起票したIssueへのリンクをまとめる形
- コミットが必要な変更がない場合、PRは作成しない

## 対象ファイル（参照のみ）
- `scripts/setup-github-project.sh` - 既存パターンの参照元
- `.github/workflows/setup-github-project.yml` - 既存ワークフローの参照元

## 検証方法
- 起票された各Issueが検討項目をカバーしているか確認
- Issueコメントの調査結果が正確か確認
