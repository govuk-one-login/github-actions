# Deletes all objects and object versions from a bucket
set -eu

: "${BUCKET}"         # Name of the bucket to empty
: "${STEP:=1000}"     # Step size when removing object versions
: "${VERBOSE:=false}" # Whether to print to step summary

$VERBOSE && step_summary=$GITHUB_STEP_SUMMARY

function get-versioning {
  aws s3api get-bucket-versioning --bucket "$BUCKET" --output text
}

function get-object-versions {
  aws s3api list-object-versions --bucket "$BUCKET" --query \
    "{Versions: Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers: DeleteMarkers[].{Key:Key,VersionId:VersionId}}"
}

function delete-objects {
  local type=$1 objects count
  objects=$(jq --compact-output ".$type" <<< "$versions")
  count=$(jq length <<< "$objects")

  [[ $count -eq 0 ]] && echo "  No $type found" && return 0
  echo "  Deleting $count $type... "

  local batch lower=0 upper=0
  while [[ $upper -lt $count ]]; do
    upper=$((upper + STEP))
    [[ $upper -gt $count ]] && upper=$count
    batch=$(jq --compact-output "{Objects: .[$lower:$upper], Quiet: true}" <<< "$objects")
    aws s3api delete-objects --bucket "$BUCKET" --delete file:///dev/stdin <<< "$batch"
    lower=$upper
  done
}

function delete-versions {
  delete-objects Versions && delete-objects DeleteMarkers
}

echo "Emptying bucket $BUCKET"

echo "  Deleting objects..."
aws s3 rm "s3://$BUCKET" --recursive --quiet

echo -n "  Checking versioning configuration... "
[[ $(get-versioning) == Enabled ]] && versioning=true && echo "[Enabled]" || echo "[Disabled]"

if ${versioning:-false}; then
  echo "  Getting object versions..."
  versions=$(get-object-versions)

  if ! delete-versions; then
    echo "❌ Failed to empty bucket \`$BUCKET\`" | tee -a "${step_summary[@]}"
    exit 1
  fi
fi

echo "🗑️ Emptied bucket \`$BUCKET\`" | tee -a "${step_summary[@]}"
