set -euo pipefail
option_regex="[[:space:]]([^-{2}]+)($| )"
base_dir="$(dirname "${BASH_SOURCE[0]}")"
report="$base_dir/../../../scripts/report-step-result/print-file.sh"

[[ ${1:-} == help ]] && echo "Using stub GitHub CLI" && exit

if [[ ${1:-} == api ]]; then
  # List artifacts for a repo
  if [[ ${2:-} =~ \/repos\/.*\/actions\/artifacts\?name=(.+) ]]; then
    artifact=${BASH_REMATCH[1]}
    source="$base_dir/data/artifacts.json"
    query=".artifacts | {artifacts: map(select(.name == \"$artifact\"))}"
    echo "[GH API] Artifact name filter: \`$artifact\`" >> "$GITHUB_STEP_SUMMARY"
  fi
elif [[ ${1:-} == run ]]; then
  source="$base_dir/data/workflows-runs.json"

  # Get a workflow run
  if [[ ${2:-} == view ]]; then
    run=$3
    options=${*:4}
    single_result=true
    title="Workflow run"
    query=".[] | select(.databaseId == $run)"
    echo "[GH CLI] Workflow run ID: \`$run\`" >> "$GITHUB_STEP_SUMMARY"
  fi

  # List workflow runs matching a query
  if [[ ${2:-} == list ]]; then
    options=${*:3}
    title="Workflow runs"

    [[ $options =~ --event$option_regex ]] && event=${BASH_REMATCH[1]}
    query=".[]${event:+"|select(.event == \"$event\")"}"

    echo "[GH CLI] Workflow runs query: \`$options\`" >> "$GITHUB_STEP_SUMMARY"
  fi
else
  echo "Unknown command: $*"
  exit 1
fi

results=$(jq "$query" "$source")

if [[ ${options:-} ]]; then
  [[ $options =~ --jq$option_regex ]] && jq=${BASH_REMATCH[1]}
  [[ $options =~ --json$option_regex ]] && json=${BASH_REMATCH[1]}

  [[ ${json:-} ]] && results=$(jq --slurp "flatten | map({$json})" <<< "$results")
  ${single_result:-false} && results=$(jq '.[]' <<< "$results")
  [[ ${jq:-} ]] && results=$(jq "$jq" <<< "$results")
fi

[[ ${title:-} ]] && TITLE=$title LANGUAGE=json $report <<< "$results" >> "$GITHUB_STEP_SUMMARY"
echo "$results"
