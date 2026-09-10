#!/usr/bin/env bash

set -euo pipefail

# only run on a pull request event
if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ] && [ "${GITHUB_EVENT_NAME:-}" != "pull_request_target" ]; then
  echo "❌ This action can only be run on pull_request or pull_request_target events."
  exit 1
fi

if [ -z "${PR_NUMBER:-}" ]; then
  echo "❌ PR_NUMBER environment variable is not set."
  exit 1
fi

echo "Fetching commit details for PR #$PR_NUMBER on repo $GITHUB_REPOSITORY"

# merge commits will have more than one parent
MERGE_COMMITS=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/commits?per_page=100" \
  --jq '.[] | select(.parents | length > 1) | "\(.sha) \(.commit.message | split("\n")[0])"')

if [ -n "$MERGE_COMMITS" ]; then
  echo "❌ Found merge commit(s) in PR #$PR_NUMBER:"
  echo "$MERGE_COMMITS" | while read -r line; do
    echo "  - $line"
  done
  echo "Please rebase your branch against the base branch and remove the merge commit(s)."
  exit 1
fi

echo "✅ No merge commits found in PR #$PR_NUMBER on repo $GITHUB_REPOSITORY"
