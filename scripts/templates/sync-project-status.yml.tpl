name: "🔄 ステータス自動同期"

on:
  issues:
    types: [opened, closed, reopened]
  pull_request:
    types: [opened, closed, review_requested, converted_to_draft, ready_for_review]
  pull_request_review:
    types: [submitted]

permissions:
  contents: read
  issues: read
  pull-requests: read

jobs:
  sync-project-status:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ secrets.PROJECT_PAT }}
      EVENT_NAME: ${{ github.event_name }}
      ACTION: ${{ github.event.action }}
      ISSUE_NODE_ID: ${{ github.event.issue.node_id }}
      PR_NODE_ID: ${{ github.event.pull_request.node_id }}
      PR_MERGED: ${{ github.event.pull_request.merged }}
      REVIEW_STATE: ${{ github.event.review.state }}
      ISSUE_NUMBER: ${{ github.event.issue.number }}
      ISSUE_TITLE: ${{ github.event.issue.title }}
      PR_NUMBER: ${{ github.event.pull_request.number }}
      PR_TITLE: ${{ github.event.pull_request.title }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6.0.2

      - name: ステータスを同期
        run: |
          chmod +x scripts/sync-project-status.sh
          bash scripts/sync-project-status.sh
