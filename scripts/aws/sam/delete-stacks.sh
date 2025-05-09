# Returns four arrays with deleted, failed, ignored and missing stacks

set -eu
base_dir="$(dirname "${BASH_SOURCE[0]}")"

: "${STACK_NAMES}"          # Names of the stacks to delete (space or newline-delimited string)
: "${ONLY_FAILED}"          # Whether to only delete stacks in one of the failed states
: "${EMPTY_BUCKETS:=false}" # Whether to empty stack buckets before deletion
: "${VERBOSE:=false}"       # Whether to print messages for non-deleted stacks

$VERBOSE && step_summary=$GITHUB_STEP_SUMMARY
report="$base_dir/../../report-step-result/print-list.sh"

stacks=$("$base_dir/../cloudformation/check-stacks-exist.sh")
missing=$(jq --raw-output '."missing-stacks"' <<< "$stacks")
existing=$(jq --raw-output '."existing-stacks"' <<< "$stacks")
failed=()

read -ra stacks <<< "$existing"

for stack in "${stacks[@]}"; do
  if $ONLY_FAILED; then
    stack_state=$(aws cloudformation describe-stacks \
      --stack-name "$stack" \
      --query "Stacks[].StackStatus" \
      --output text)

    if ! [[ $stack_state =~ _FAILED$|^ROLLBACK_COMPLETE$ ]]; then
      ignored+=("$stack")
      continue
    fi
  fi

  if $EMPTY_BUCKETS; then
    buckets=$(STACK_NAME=$stack VERBOSE=$VERBOSE "$base_dir/../cloudformation/list-stack-buckets.sh")

    if [[ $buckets ]]; then
      VALUES=$buckets CODE_BLOCK=false MESSAGE="Found buckets in stack $stack" $report
      for bucket in $buckets; do BUCKET=$bucket VERBOSE=$VERBOSE "$base_dir/../s3/empty-bucket.sh"; done
    fi
  fi

  sam delete --no-prompts --region "$AWS_REGION" --stack-name "$stack" && deleted+=("$stack") || failed+=("$stack")
done

VALUES=${missing[*]} MESSAGE="Non-existent stacks" SINGLE_MESSAGE="Stack %s does not exist" $report |
  tee -a "${step_summary[@]}"

VALUES=${ignored[*]} MESSAGE="Ignored stacks in a good state" SINGLE_MESSAGE="Ignored stack %s in a good state" $report |
  tee -a "${step_summary[@]}"

VALUES=${deleted[*]} MESSAGE="🚮 Deleted stacks" SINGLE_MESSAGE="🚮 Deleted stack %s" $report |
  tee -a "$GITHUB_STEP_SUMMARY"

VALUES=${failed[*]} MESSAGE="❌ Failed to delete stacks" SINGLE_MESSAGE="❌ Failed to delete stack %s" $report |
  tee -a "$GITHUB_STEP_SUMMARY"

{
  echo "deleted-stacks=${deleted[*]}"
  echo "failed-stacks=${failed[*]}"
  echo "ignored-stacks=${ignored[*]}"
  echo "missing-stacks=${missing[*]}"
} >> "$GITHUB_OUTPUT"

[[ ${#failed[@]} -eq 0 ]] || exit 1
