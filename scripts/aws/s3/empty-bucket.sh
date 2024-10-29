# Deletes all current objects from a bucket
set -eu

: "${BUCKET}"        # Name of the bucket to empty
: "${VERBOSE:=true}" # Whether to print to step summary

echo "Deleting objects from bucket $BUCKET"
aws s3 rm "s3://$BUCKET" --recursive --quiet

$VERBOSE && step_summary=$GITHUB_STEP_SUMMARY
echo "Emptied bucket \`$BUCKET\`" | tee -a "${step_summary[@]}"
