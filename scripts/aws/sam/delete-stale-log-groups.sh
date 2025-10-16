# Deletes stale CloudWatch log groups that are unmanaged and match known patterns, prints a report of unknown patterns that could be deleted
set -eu

base_dir="$(dirname "${BASH_SOURCE[0]}")"
report="$base_dir/../../report-step-result/print-list.sh"

: "${DESTRUCTIVE:=false}"
: "${CUTOFF_DAYS:=30}"
: "${VERBOSE:=false}"
: "${LIMIT:=}"
: "${SAFE_PATTERNS:=}" # /pre-merge-|^API-Gateway-Execution-Logs_

if $DESTRUCTIVE; then
  echo "🚨 DESTRUCTIVE is true, resources will be deleted 🚨"
fi

$VERBOSE && step_summary=$GITHUB_STEP_SUMMARY

current_time_ms=${CURRENT_TIME_MS:-$(($(printf '%(%s)T') * 1000))} # allow override for tests
cutoff_timestamp=$((current_time_ms - CUTOFF_DAYS * 86400000))

echo "Stale cutoff timestamp(ms): $cutoff_timestamp" | tee -a "${step_summary:-/dev/null}"

output_dir=$(mktemp -d)
trap 'if [[ -n "$output_dir" && "$output_dir" == /tmp/* ]]; then rm -rf "$output_dir"; fi' EXIT

function fetch-log-groups {
  local count
  aws logs describe-log-groups --output json > "$output_dir/log_groups.json"
  count=$(jq '.logGroups | length' "$output_dir/log_groups.json")
  echo "Found $count log groups" | tee -a "${step_summary:-/dev/null}"
}

function filter-stale-log-groups {
  local count
  jq '[.logGroups[] | select(.storedBytes == 0 and .creationTime < '"$cutoff_timestamp"')]' \
    "$output_dir/log_groups.json" > "$output_dir/stale_log_groups.json"
  count=$(jq '. | length' "$output_dir/stale_log_groups.json")
  echo "Found $count stale log groups" | tee -a "${step_summary:-/dev/null}"
  if [[ $count -eq 0 ]]; then
    echo "ℹ️ No stale log groups found, exiting early" | tee -a "${step_summary:-/dev/null}"
    exit 0
  fi
}

function fetch-stack-resources {
  local stack_count
  aws cloudformation describe-stacks --output json |
    jq -r '.Stacks[] | select(.StackStatus != "DELETE_COMPLETE") | .StackName' \
      > "$output_dir/stack_names.txt"
  stack_count=$(grep -c . "$output_dir/stack_names.txt" || echo 0)
  echo "Found $stack_count CloudFormation stacks" | tee -a "${step_summary:-/dev/null}"

  if [[ $stack_count -eq 0 ]]; then
    echo "ℹ️ No CloudFormation stacks found, exiting early" | tee -a "${step_summary:-/dev/null}"
    exit 0
  fi

  local process_count=0
  touch "$output_dir/cf_stack_resources_raw.json"
  while read -r stack; do
    ((++process_count))
    echo "  Processing stack $process_count/$stack_count: $stack"
    aws cloudformation describe-stack-resources --stack-name "$stack" --output json 2> /dev/null >> "$output_dir/cf_stack_resources_raw.json"
  done < "$output_dir/stack_names.txt"

  jq -s '.' "$output_dir/cf_stack_resources_raw.json" > "$output_dir/cf_stack_resources.json" # combine
}

function extract-managed-log-groups {
  local count
  jq '[.[].StackResources[]? | select(.ResourceType == "AWS::Logs::LogGroup") | .PhysicalResourceId]' \
    "$output_dir/cf_stack_resources.json" > "$output_dir/cf_managed_log_groups.json"
  count=$(jq '. | length' "$output_dir/cf_managed_log_groups.json")
  echo "Found $count managed log groups" | tee -a "${step_summary:-/dev/null}"
}

function identify-safe-to-delete {
  local count
  jq --slurpfile cf "$output_dir/cf_managed_log_groups.json" \
    '[.[] | select([.logGroupName] | inside($cf[0]) | not)]' \
    "$output_dir/stale_log_groups.json" > "$output_dir/stale_unmanaged_log_groups.json"
  count=$(jq '. | length' "$output_dir/stale_unmanaged_log_groups.json")
  echo "Found $count stale unmanaged log groups" | tee -a "${step_summary:-/dev/null}"

  if [[ -z "$SAFE_PATTERNS" ]]; then
    echo "⚠️ No patterns are defined, all results require manual review" | tee -a "${step_summary:-/dev/null}"
    jq -r '.[] | .logGroupName' \
      "$output_dir/stale_unmanaged_log_groups.json" > "$output_dir/review_for_deletion.txt"
    touch "$output_dir/safe_to_delete.txt"
  else
    echo "Looking for safe patterns: $SAFE_PATTERNS" | tee -a "${step_summary:-/dev/null}"
    jq --arg patterns "$SAFE_PATTERNS" -r \
      '.[] | .logGroupName | select(test($patterns) | not)' \
      "$output_dir/stale_unmanaged_log_groups.json" > "$output_dir/review_for_deletion.txt"

    jq --arg patterns "$SAFE_PATTERNS" -r \
      '.[] | .logGroupName | select(test($patterns))' \
      "$output_dir/stale_unmanaged_log_groups.json" |
      if [[ -n "$LIMIT" ]]; then
        head -n "$LIMIT"
      else
        cat
      fi > "$output_dir/safe_to_delete.txt"
  fi
}

echo "Fetching log groups..."
fetch-log-groups
echo "Filtering stale log groups (empty and older than $CUTOFF_DAYS days)..."
filter-stale-log-groups
echo "Fetching stack resources (this will take a few minutes)..."
fetch-stack-resources
echo "Extracting managed log groups..."
extract-managed-log-groups
echo "Identifying stale unmanaged log groups..."
identify-safe-to-delete

stale_total=$(jq '. | length' "$output_dir/stale_log_groups.json")
stale_managed=$(jq --slurpfile cf "$output_dir/cf_managed_log_groups.json" '[.[] | select([.logGroupName] | inside($cf[0]))] | length' "$output_dir/stale_log_groups.json")
stale_unmanaged=$(jq '. | length' "$output_dir/stale_unmanaged_log_groups.json")
safe_to_delete_count=$(grep -c . "$output_dir/safe_to_delete.txt" 2> /dev/null || safe_to_delete_count=0)
review_count=$(grep -c . "$output_dir/review_for_deletion.txt" 2> /dev/null || review_count=0)

echo ""
echo "Summary:"
echo "  Total stale log groups: $stale_total"
echo "  Managed (stale): $stale_managed"
echo "  Unmanaged (stale): $stale_unmanaged"
if [[ -n "$LIMIT" ]]; then
  echo "    - Safe to delete (known patterns): $safe_to_delete_count (limited to $LIMIT)"
else
  echo "    - Safe to delete (known patterns): $safe_to_delete_count"
fi
echo "    - Needs review: $review_count"
echo ""

if [[ $review_count -gt 0 ]]; then
  mapfile -t review_items < "$output_dir/review_for_deletion.txt"
  VALUES="${review_items[*]}" MESSAGE="⚠️ Log groups requiring manual review" SINGLE_MESSAGE="⚠️ Log group requiring manual review %s" $report |
    tee -a "${step_summary:-/dev/null}"
fi

if $DESTRUCTIVE; then
  if [[ $safe_to_delete_count -eq 0 ]]; then
    echo "✅ No log groups eligible for deletion" | tee -a "${step_summary:-/dev/null}"
  else
    count=0
    while read -r log_group; do
      ((++count))
      printf "\rDeleting log group %d of %d..." "$count" "$safe_to_delete_count"
      if aws logs delete-log-group --log-group-name "$log_group" 2> /dev/null; then
        echo "SUCCESS:$log_group" >> "$output_dir/deletion_results.txt"
      else
        echo "FAILED:$log_group" >> "$output_dir/deletion_results.txt"
      fi
      sleep 0.25 # rate limiting: ~3 deletions/sec
    done < "$output_dir/safe_to_delete.txt"
    echo ""

    mapfile -t results < "$output_dir/deletion_results.txt"

    deleted=()
    failed=()
    for result in "${results[@]}"; do
      status="${result%%:*}"   # everything before first colon
      log_group="${result#*:}" # everything after first colon

      if [[ "$status" == "SUCCESS" ]]; then
        deleted+=("$log_group")
      else
        failed+=("$log_group")
      fi
    done

    VALUES="${deleted[*]}" MESSAGE="✅ Deleted log groups" SINGLE_MESSAGE="✅ Deleted log group %s" $report |
      tee -a "${step_summary:-/dev/null}"

    VALUES="${failed[*]}" MESSAGE="❌ Failed to delete log groups" SINGLE_MESSAGE="❌ Failed to delete log group %s" $report |
      tee -a "${step_summary:-/dev/null}"
  fi

  {
    echo "deleted-count=${#deleted[@]}"
    echo "failed-count=${#failed[@]}"
    echo "review-count=$review_count"
    echo "stale-total=$stale_total"
  } >> "${GITHUB_OUTPUT:-/dev/null}"

  [[ ${#failed[@]} -eq 0 ]] || exit 1
else
  mapfile -t safe_to_delete < "$output_dir/safe_to_delete.txt"

  VALUES="${safe_to_delete[*]}" MESSAGE="ℹ️ (dry run) Would delete log groups" SINGLE_MESSAGE="ℹ️ (dry run) Would delete log group %s" $report |
    tee -a "${step_summary:-/dev/null}"

  {
    echo "would-delete-count=$safe_to_delete_count"
    echo "review-count=$review_count"
    echo "stale-total=$stale_total"
  } >> "${GITHUB_OUTPUT:-/dev/null}"
fi
