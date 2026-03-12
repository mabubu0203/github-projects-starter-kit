# ① GitHub Project 新規作成

新しい Project を作成し、カスタムフィールド・ステータスカラム・View を一括でセットアップします。

## 使い方

1. `Actions` タブを開く
2. `① GitHub Project 新規作成` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

## パラメータ

| パラメータ | 説明 | 必須 | 例 |
|------------|------|:----:|-----|
| `project_title` | Project のタイトル | ✅ | `My Project Board` |
| `visibility` | Project の公開範囲 | ✅ | `PRIVATE`（デフォルト） / `PUBLIC` |

> **Note:** Project の Owner はリポジトリの Owner から自動取得されます。
> カスタムフィールド・ステータスカラム・View の定義は各スクリプト内に固定されています。カスタマイズする場合はスクリプトを直接編集してください。

## 処理シーケンス

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant WF as 01-create-project.yml
    participant S1 as setup-github-project.sh
    participant RW as _reusable-extend-project.yml
    participant S2 as setup-project-fields.sh
    participant S3 as setup-status-columns.sh
    participant S4 as create-project-views.sh

    User->>WF: workflow_dispatch（タイトル・公開範囲）
    Note over WF: create-project ジョブ
    WF->>S1: Project を作成
    S1-->>WF: project_number

    Note over WF: extend-project ジョブ
    WF->>RW: project_number を渡して呼び出し
    RW->>S2: カスタムフィールドを作成
    S2-->>RW: 完了
    RW->>S3: ステータスカラムを設定
    S3-->>RW: 完了
    RW->>S4: View を作成
    S4-->>RW: 完了
    RW-->>WF: 完了
```
