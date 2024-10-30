# Returns the names of all of the buckets in a stack

set -eu
base_dir="$(dirname "${BASH_SOURCE[0]}")"
report="$base_dir"/../../report-step-result/print-list.sh

: "${STACK_NAME}"          # Name of the stack containing the buckets to list
: "${VERBOSE:=false}"      # Whether to print to step summary
: "${ERROR_STATUS:=false}" # Whether to exit with an error status if no buckets have been found

buckets=$(aws cloudformation list-stack-resources \
  --stack-name "$STACK_NAME" \
  --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
  --output text)

if ! [[ $buckets ]]; then
  $VERBOSE && echo "No buckets found in stack $STACK_NAME" >> "$GITHUB_STEP_SUMMARY"
  $ERROR_STATUS && exit 1 || exit 0
fi

$VERBOSE && VALUES="$buckets" MESSAGE="🪣 Found buckets in stack \`$STACK_NAME\`" \
  SINGLE_MESSAGE="🪣 Found a bucket in stack \`$STACK_NAME\`" $report >> "$GITHUB_STEP_SUMMARY"

echo "$buckets"
