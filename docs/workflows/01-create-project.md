# ① 📝 GitHub Project 新規作成

新しい `Project` を作成し、カスタムフィールド・ステータスカラム・`View` を一括でセットアップします。

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**

- [✅ 前提](#-%E5%89%8D%E6%8F%90)
- [📖 使い方](#-%E4%BD%BF%E3%81%84%E6%96%B9)
- [⚙️ パラメータ](#-%E3%83%91%E3%83%A9%E3%83%A1%E3%83%BC%E3%82%BF)
  - [公開範囲](#%E5%85%AC%E9%96%8B%E7%AF%84%E5%9B%B2)
- [📊 処理フロー](#-%E5%87%A6%E7%90%86%E3%83%95%E3%83%AD%E3%83%BC)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## ✅ 前提

このワークフローを実行する前に、クイックスタートを完了してください。

- [クイックスタート（GUI）](../quickstart-gui)
- [クイックスタート（CLI）](../quickstart-cli)

## 📖 使い方

1. `Actions` タブを開く
2. `① GitHub Project 新規作成` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

## ⚙️ パラメータ

| パラメータ | 説明 | 必須 | タイプ | 例 |
|------------|------|:----:|--------|-----|
| `project_title` | `Project` のタイトル | ✅ | `string` | `My Project Board` |
| `visibility` | `Project` の公開範囲 | ✅ | `choice` | `PRIVATE`（デフォルト） |

### 公開範囲

| 選択肢 | 説明 |
|--------|------|
| `PRIVATE` | 自分のみ閲覧可能 |
| `PUBLIC` | 誰でも閲覧可能 |

## 📊 処理フロー

```mermaid
flowchart TD
    A["workflow_dispatch\n（タイトル・公開範囲）"] --> B["create-project ジョブ\nProject を新規作成し project_number を出力"]
    B -- "成功" --> C["extend-project ジョブ\nフィールド・ステータス・View を一括セットアップ"]
    B -- "失敗" --> D["extend-project スキップ"]
    C --> E{"全体結果判定"}
    D --> E
    E -- "成功" --> F["workflow-summary-success ジョブ\n成功サマリーを出力"]
    E -- "失敗" --> G["workflow-summary-failure ジョブ\n失敗サマリーを出力"]
```
