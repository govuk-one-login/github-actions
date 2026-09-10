#!/usr/bin/env bash

set -euo pipefail

CHECK_MERGE_COMMITS_SCRIPT="$(dirname "$0")/../../../../scripts/code-quality/check-merge-commits/check-merge-commits.sh"

echo "Test 1: Verifying non-PR event fails"

export GITHUB_EVENT_NAME="push"
export PR_NUMBER="123"

set +e
CHECK_MERGE_COMMITS_SCRIPT_OUTPUT=$("$CHECK_MERGE_COMMITS_SCRIPT" 2>&1)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "✅ PASS: Script correctly failed on non-PR event."
else
  echo "❌ FAIL: Script should have failed on non-PR event."
  echo "Output: $CHECK_MERGE_COMMITS_SCRIPT_OUTPUT"
  exit 1
fi

echo ""
echo "Test 2: Verifying PR with no merge commits passes"
export GITHUB_EVENT_NAME="pull_request"
export PR_NUMBER="36" # PR number with no merge commits

if "$CHECK_MERGE_COMMITS_SCRIPT"; then
  echo "✅ PASS: PR with no merge commits passed as expected."
else
  echo "❌ FAIL: PR with no merge commits unexpectedly failed."
  exit 1
fi

echo ""
echo "Test 3: Verifying PR with merge commits fails"
export GITHUB_EVENT_NAME="pull_request"
export PR_NUMBER="37" # PR number that contains a merge commit

set +e
CHECK_MERGE_COMMITS_SCRIPT_OUTPUT=$("$CHECK_MERGE_COMMITS_SCRIPT" 2>&1)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "✅ PASS: Script correctly failed on PR with merge commits."
else
  echo "❌ FAIL: Script unexpectedly passed on PR with merge commits."
  echo "Output: $CHECK_MERGE_COMMITS_SCRIPT_OUTPUT"
  exit 1
fi

echo ""
echo "🎉 All tests passed successfully!"
