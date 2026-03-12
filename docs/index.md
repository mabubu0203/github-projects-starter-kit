# GitHub Projects Starter Kit ドキュメント

GitHub Projects の初期セットアップを GitHub Actions で自動実行するための **スターターキット** です。

## ワークフロー一覧

| ワークフロー | 説明 | トリガー |
|------------|------|---------|
| ① GitHub Project 新規作成 | Project の作成・フィールド・ステータス・View を一括セットアップ | `workflow_dispatch`（手動実行） |
| ② GitHub Project 拡張 | 既存 Project にフィールド・ステータス・View を追加 | `workflow_dispatch`（手動実行） |
| ③ Issue/PR 一括紐付け | リポジトリの Issue/PR を Project に一括追加 | `workflow_dispatch`（手動実行） |

## クイックスタート

### 1. リポジトリを fork する

本リポジトリを自分のアカウントまたは Organization に fork してください。

### 2. PAT を作成する

GitHub の [Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens) から PAT を作成します。

**Fine-grained token の場合:**

- `Organization permissions` > `Projects` > `Read and write`（Organization）
- `Account permissions` > `Projects` > `Read and write`（個人）

**Classic token の場合:**

- `project` スコープ

### 3. Secrets を設定する

fork 先リポジトリの `Settings > Secrets and variables > Actions` で以下を追加します。

| Secret 名 | 説明 |
|------------|------|
| `PROJECT_PAT` | 作成した PAT |

### 4. ワークフローを実行する

#### ① GitHub Project 新規作成

新しい Project を作成し、カスタムフィールド・ステータスカラム・View を一括でセットアップします。

1. `Actions` タブを開く
2. `① GitHub Project 新規作成` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

| パラメータ | 説明 | 必須 | 例 |
|------------|------|:----:|-----|
| `project_title` | Project のタイトル | ✅ | `My Project Board` |
| `visibility` | Project の公開範囲 | ✅ | `PRIVATE`（デフォルト） / `PUBLIC` |
| `field_definitions` | カスタムフィールド定義（JSON 配列） | - | デフォルトあり |
| `status_options` | ステータスカラム定義（JSON 配列） | - | デフォルトあり |
| `view_definitions` | View 定義（JSON 配列） | - | デフォルトあり |

> **Note:** Project の Owner はリポジトリの Owner から自動取得されます。

#### ② GitHub Project 拡張

既存の Project にカスタムフィールド・ステータスカラム・View を追加します。
①を実行していない既存 Project 向けです。

1. `Actions` タブを開く
2. `② GitHub Project 拡張` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

| パラメータ | 説明 | 必須 | 例 |
|------------|------|:----:|-----|
| `project_number` | 対象 Project の Number | ✅ | `1` |
| `field_definitions` | カスタムフィールド定義（JSON 配列） | - | デフォルトあり |
| `status_options` | ステータスカラム定義（JSON 配列） | - | デフォルトあり |
| `view_definitions` | View 定義（JSON 配列） | - | デフォルトあり |

#### ③ Issue/PR 一括紐付け

リポジトリの Issue/PR を Project に一括追加します。

1. `Actions` タブを開く
2. `③ Issue/PR 一括紐付け` を選択
3. `Run workflow` をクリック
4. パラメータを入力して実行

| パラメータ | 説明 | 必須 | 例 |
|------------|------|:----:|-----|
| `project_number` | 対象 Project の Number | ✅ | `1` |
| `target_repo` | 対象リポジトリ（owner/repo 形式） | ✅ | `myorg/myrepo` |
| `include_issues` | Issue を追加対象にする | ✅ | `true`（デフォルト） |
| `include_prs` | Pull Request を追加対象にする | ✅ | `true`（デフォルト） |
| `item_state` | 取得するアイテムの状態 | - | `open`（デフォルト） |
| `item_label` | 絞り込みラベル（指定ラベルのみ追加） | - | `bug` |

> **Note:** 既に Project に追加済みのアイテムは自動的にスキップされます。

## スクリプト詳細

### setup-github-project.sh

Project を新規作成します。

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_TITLE` | 作成する Project のタイトル | ✅ |
| `PROJECT_VISIBILITY` | Project の公開範囲（`PUBLIC` / `PRIVATE`） | ❌（デフォルト: `PRIVATE`） |

### setup-project-fields.sh

Project にカスタムフィールドを自動作成します。

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |
| `FIELD_DEFINITIONS` | フィールド定義（JSON 配列） | ✅ |

**対応データ型:** `TEXT`, `SINGLE_SELECT`, `DATE`, `NUMBER`

> **Note:** 既に同名のフィールドが存在する場合は自動的にスキップされます。

### setup-status-columns.sh

Project の Status カラムをテンプレートで設定します。

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |
| `STATUS_OPTIONS` | ステータスカラム定義（JSON 配列） | ✅ |

**対応カラー:** `GRAY`, `BLUE`, `GREEN`, `YELLOW`, `ORANGE`, `RED`, `PINK`, `PURPLE`

### create-project-views.sh

Project に View を自動作成します。

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |
| `VIEW_DEFINITIONS` | View 定義（JSON 配列） | ❌（デフォルトあり） |

**対応レイアウト:** `TABLE_LAYOUT`, `BOARD_LAYOUT`, `ROADMAP_LAYOUT`

**デフォルト View:** `VIEW_DEFINITIONS` を省略した場合、以下の3件が作成されます。

- `Table`（TABLE_LAYOUT）
- `Board`（BOARD_LAYOUT）
- `Roadmap`（ROADMAP_LAYOUT）

### add-items-to-project.sh

リポジトリの Issue/PR を Project に一括追加します。

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

> **Note:** 既に Project に追加済みのアイテムは自動的にスキップされます。

## 構成ファイル

```
.github/workflows/
  ├── 01-create-project.yml       # ① Project 新規作成ワークフロー
  ├── 02-extend-project.yml       # ② Project 拡張ワークフロー
  └── 03-add-items-to-project.yml # ③ Issue/PR 一括紐付けワークフロー
scripts/
  ├── setup-github-project.sh     # Project 作成スクリプト
  ├── setup-project-fields.sh     # カスタムフィールド作成スクリプト
  ├── setup-status-columns.sh     # ステータスカラム設定スクリプト
  ├── create-project-views.sh     # View 作成スクリプト
  └── add-items-to-project.sh     # アイテム一括追加スクリプト
```

## リポジトリ

- GitHub: [mabubu0203/github-projects-starter-kit](https://github.com/mabubu0203/github-projects-starter-kit)
