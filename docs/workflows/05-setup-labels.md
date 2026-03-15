# ⑤ 🏷️ Issue ラベル一括追加

<!-- START doctoc -->
<!-- END doctoc -->

指定リポジトリに対して、設定ファイルで定義した Issue ラベルを一括作成します。

## ✅ 前提

このワークフローを実行する前に、クイックスタートを完了してください。

- [クイックスタート（GUI）](../quickstart-gui)
- [クイックスタート（CLI）](../quickstart-cli)

## 📖 使い方

1. `Actions` タブを開く
2. `⑤ Issue ラベル一括追加` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

## ⚙️ パラメータ

| パラメータ | 説明 | 必須 | タイプ | 例 |
|------------|------|:----:|--------|-----|
| `target_repo` | 対象リポジトリ（owner/repo 形式） | ✅ | `string` | `myorg/myrepo` |
| `force_update` | 既存ラベルの上書き更新 | ✅ | `boolean` | `false`（デフォルト） |

### 上書きモード

| 設定値 | 動作 |
|--------|------|
| `false`（デフォルト） | 既存ラベルと同名のラベルはスキップ（安全モード） |
| `true` | 既存ラベルの色・説明を定義ファイルの内容で上書き更新 |

> **Note:** いずれのモードでも、定義ファイルに含まれない既存ラベルは削除されません。追加・更新のみの安全設計です。

## 📊 処理フロー

```mermaid
flowchart TD
    A["workflow_dispatch\n（target_repo・force_update）"] --> B["setup-labels ジョブ\nラベル定義ファイルを読み込み\n対象リポジトリにラベルを一括作成"]
    B --> C{"結果判定"}
    C -- "成功" --> D["workflow-summary-success ジョブ\n成功サマリーを出力"]
    C -- "失敗" --> E["workflow-summary-failure ジョブ\n失敗サマリーを出力"]
```

## 🔧 ワークフロー仕様

### ファイル

`05-setup-labels.yml`

### トリガー

`workflow_dispatch`（手動実行）

### 権限

```yaml
permissions:
  contents: read
```

### 環境変数

| 環境変数 | ソース | 説明 |
|----------|--------|------|
| `GH_TOKEN` | `secrets.PROJECT_PAT` | GitHub PAT（`repo` スコープ必須） |
| `TARGET_REPO` | `inputs.target_repo` | 対象リポジトリ |
| `FORCE_UPDATE` | `inputs.force_update` | 上書きモード |

### ジョブ構成

```
05-setup-labels.yml
  ├── setup-labels ジョブ
  │   └── scripts/setup-labels.sh          # ラベル一括作成
  ├── workflow-summary-failure ジョブ（失敗時）
  │   └── .github/actions/workflow-summary  # 失敗サマリー出力
  └── workflow-summary-success ジョブ（成功時）
      └── .github/actions/workflow-summary  # 成功サマリー出力
```

## 📜 関連スクリプト

- [setup-labels.sh](../scripts/setup-labels) — ラベル一括作成スクリプト
