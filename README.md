# github-projects-starter-kit

GitHub Projects Starter Kit

## 概要

GitHub Projects の初期セットアップを GitHub Actions で自動実行するためのスターターキットです。
本リポジトリを fork し、GitHub Actions を手動実行することで、GitHub Project を作成できます。

## セットアップ手順

### 1. リポジトリを fork する

本リポジトリを自分のアカウントまたは Organization に fork してください。

### 2. Personal Access Token (PAT) を作成する

GitHub の [Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens) から PAT を作成してください。

#### 必要な権限

- **Fine-grained token** の場合:
  - `Organization permissions` > `Projects` > `Read and write`（Organization の場合）
  - `Account permissions` > `Projects` > `Read and write`（個人の場合）

- **Classic token** の場合:
  - `project` スコープ

### 3. Secrets を設定する

fork したリポジトリの `Settings > Secrets and variables > Actions` で以下の Secret を追加してください。

| Secret 名 | 説明 |
|------------|------|
| `PROJECT_PAT` | 上記で作成した PAT |

### 4. GitHub Actions を実行する

1. リポジトリの `Actions` タブを開く
2. 左メニューから `Setup GitHub Project` を選択
3. `Run workflow` をクリック
4. 以下のパラメータを入力して実行

| パラメータ | 説明 | 例 |
|------------|------|-----|
| `project_title` | Project のタイトル | `My Project Board` |

> **Note:** Project の Owner はリポジトリの Owner（個人アカウントまたは Organization）から自動取得されます。

## ライセンス

[MIT License](LICENSE)
