# ② GitHub Project 拡張

既存の Project にカスタムフィールド・ステータスカラム・View を追加します。
[① GitHub Project 新規作成](01-create-project) を実行していない既存 Project 向けです。

## 使い方

1. `Actions` タブを開く
2. `② GitHub Project 拡張` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

## パラメータ

| パラメータ | 説明 | 必須 | 例 |
|------------|------|:----:|-----|
| `project_number` | 対象 Project の Number | ✅ | `1` |

## 処理シーケンス

```mermaid
sequenceDiagram
    actor User as ユーザー
    participant WF as 02-extend-project.yml
    participant RW as _reusable-extend-project.yml
    participant S2 as setup-project-fields.sh
    participant S3 as setup-status-columns.sh
    participant S4 as create-project-views.sh

    User->>WF: workflow_dispatch（project_number）
    Note over WF: extend-project ジョブ
    Note over WF: ※ Project 作成ステップなし（既存 Project を使用）
    WF->>RW: project_number を渡して呼び出し
    RW->>S2: カスタムフィールドを作成
    S2-->>RW: 完了
    RW->>S3: ステータスカラムを設定
    S3-->>RW: 完了
    RW->>S4: View を作成
    S4-->>RW: 完了
    RW-->>WF: 完了
```
