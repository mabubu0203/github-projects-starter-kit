# よくある質問（FAQ）

ワークフロー利用時につまづきやすいポイントをまとめています。

---

## Q1. `project_number` はどこで確認できますか？

GitHub Project の URL 末尾の数字が `project_number` です。

| 所有者タイプ | URL 形式 |
|------------|----------|
| ユーザー | `https://github.com/users/{owner}/projects/{number}` |
| 組織（Organization） | `https://github.com/orgs/{owner}/projects/{number}` |

**例:** `https://github.com/users/octocat/projects/3` → `project_number` は **3**

### CLI で確認する方法

```bash
gh project list
```

出力の `NUMBER` 列が `project_number` に対応します。

---

## Q2. `target_repo` はどこで確認できますか？

リポジトリページの URL から `owner/repo` 形式で指定します。

**例:** `https://github.com/octocat/my-app` → `target_repo` は **octocat/my-app**

### CLI で確認する方法

```bash
gh repo list
```

出力にリポジトリが `owner/repo` 形式で表示されます。

---

## Q3. Issue や Pull Request はどこで確認できますか？

リポジトリページ上部のタブから確認できます。

| タブ | URL 形式 |
|------|----------|
| Issues | `https://github.com/{owner}/{repo}/issues` |
| Pull requests | `https://github.com/{owner}/{repo}/pulls` |

### CLI で確認する方法

```bash
# Issue 一覧
gh issue list -R owner/repo

# Pull Request 一覧
gh pr list -R owner/repo
```
