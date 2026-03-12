# setup-project-fields.sh

Project にカスタムフィールドを自動作成するスクリプトです。
既に同名のフィールドが存在する場合は自動的にスキップされます。

## 環境変数

| 環境変数 | 説明 | 必須 |
|----------|------|:----:|
| `GH_TOKEN` | GitHub PAT（Projects 操作権限が必要） | ✅ |
| `PROJECT_OWNER` | Project の所有者 | ✅ |
| `PROJECT_NUMBER` | 対象 Project の Number（数値） | ✅ |

## 作成されるフィールド

| フィールド名 | データ型 | 選択肢 |
|-------------|---------|--------|
| Priority | SINGLE_SELECT | P0, P1, P2, P3 |
| Estimate | SINGLE_SELECT | XS, S, M, L, XL |
| Category | SINGLE_SELECT | Bug, Feature, Chore, Spike |
| Due Date | DATE | - |

## フィールド構成図

```mermaid
graph TD
    Project["Project"] --> Priority["Priority\n(SINGLE_SELECT)"]
    Project --> Estimate["Estimate\n(SINGLE_SELECT)"]
    Project --> Category["Category\n(SINGLE_SELECT)"]
    Project --> DueDate["Due Date\n(DATE)"]

    Priority --> P0["P0"]
    Priority --> P1["P1"]
    Priority --> P2["P2"]
    Priority --> P3["P3"]

    Estimate --> XS["XS"]
    Estimate --> S["S"]
    Estimate --> M["M"]
    Estimate --> L["L"]
    Estimate --> XL["XL"]

    Category --> Bug["Bug"]
    Category --> Feature["Feature"]
    Category --> Chore["Chore"]
    Category --> Spike["Spike"]
```

## 使用ワークフロー

- [① GitHub Project 新規作成](../01-create-project)
- [② GitHub Project 拡張](../02-extend-project)
