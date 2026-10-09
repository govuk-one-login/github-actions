#!/usr/bin/env bash
# Runs a comma separated list of pre-commit hooks (or all hooks if none given),
# stopping at the first failure.
# pre-commit can only run one specific hook at a time - it doesn't allow passing
# in a list of hooks to run.
set -euo pipefail

read -ra args < <(xargs <<< "${ARGS}")
IFS=', ' read -ra hooks <<< "${HOOKS}"

run-pre-commit() {
  local rc=0
  pre-commit run --show-diff-on-failure --color=always "${args[@]}" "$@" || rc=$?
  if [[ $rc -ne 0 ]]; then
    git restore .
    pre-commit run --show-diff-on-failure --color=never "${args[@]}" "$@" >> "$OUTPUT_FILE" || true
  fi
  return "$rc"
}

# Run hooks one by one or all hooks if none are specified
if [[ ${#hooks[@]} -eq 0 ]]; then
  run_pre_commit || exit $?
  exit 0
fi
else
  for hook in "${hooks[@]}"; do
  run_pre_commit "$hook" || exit $?
  done
fi
