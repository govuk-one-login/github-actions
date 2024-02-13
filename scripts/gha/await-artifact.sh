# Wait for an artifact with the given name to be uploaded by any workflow run in the repository
# with the same branch and SHA as the event that triggered the current action (unless overridden by env vars).
# Returns the ID of the workflow run hosting the desired artifact if found.
base_dir="$(dirname "${BASH_SOURCE[0]}")"
set -euo pipefail

# GitHub variable overrides
: "${GH_RUN_ID:=$GITHUB_RUN_ID}"
: "${GH_HEAD_REF:=$GITHUB_HEAD_REF}"
: "${GH_REF_NAME:=$GITHUB_REF_NAME}"
: "${GH_EVENT_PATH:=$GITHUB_EVENT_PATH}"
: "${GH_EVENT_NAME:=$GITHUB_EVENT_NAME}"

# Input variables
: "${RUN_ID:-}"                   # Search for the artifact in the specified workflow run, otherwise search in all runs
: "${BRANCH:-}"                   # Search for an artifact uploaded for the specified branch
: "${HEAD_SHA:-}"                 # Search for an artifact uploaded for the specified SHA
: "${TIMESTAMP:-}"                # Search for an artifact uploaded after the specified timestamp
: "${GITHUB_TOKEN}"               # The token to authenticate to the GitHub API
: "${ARTIFACT_NAME}"              # Find an artifact with the specified name
: "${EXCLUDE_CURRENT_RUN:=false}" # Exclude artifacts from the workflow running this script

# Derived variables
: "${BRANCH:=${GH_HEAD_REF:-$GH_REF_NAME}}"
: "${HEAD_SHA:=$(jq --raw-output '.pull_request.head.sha // .head_commit.id' < "$GH_EVENT_PATH")}"
: "${TIMESTAMP:=$(jq --raw-output '.pull_request.updated_at // .head_commit.timestamp' < "$GH_EVENT_PATH")}"

function getArtifacts() {
  artifacts=$(gh api "/repos/{owner}/{repo}/actions/artifacts?name=$ARTIFACT_NAME")
  jq '.artifacts[] | select(.workflow_run.id == 7886689117)' <<< "$artifacts"
}

function getWorkflowRun() {
  PARAMETERS="$(gh run view "$run_id" --json name,number,displayTitle,url --jq 'to_entries[] | "\(.key)=\(.value)"')" \
  ASSOCIATIVE_ARRAY=true "$base_dir/../parse-parameters.sh"
}

function checkRunningWorkflows() {
  workflows=$(gh run list --json "databaseId,status" \
    --user "$GITHUB_ACTOR" \
    --branch "$BRANCH" \
    --commit "$HEAD_SHA" \
    --created ">=$TIMESTAMP" \
    --event "$GH_EVENT_NAME")

  jq --exit-status --argjson id "$GH_RUN_ID" \
    '.[] | select(.databaseId != $id and .status != "completed")' <<< "$workflows" > /dev/null &&
    awaiting_workflows=true || awaiting_workflows=false
}

function searchArtifact() {
  runs=$(jq 'map(.databaseId)' <<< "$workflows")

  getArtifacts
  artifact=$(echo "$artifacts" |
    jq --exit-status \
      --arg branch "$BRANCH" --arg sha "$HEAD_SHA" --arg event_start "$TIMESTAMP" --arg run_id "${RUN_ID:-}" \
      --argjson current_run_id "$GH_RUN_ID" --argjson exclude_current_run $EXCLUDE_CURRENT_RUN --argjson runs "$runs" \
      '.artifacts |

      # Filter artifacts
      map(
        # Select artifacts from valid workflow runs
        select(.workflow_run.id | IN($runs[])) |

        # Select artifacts created after the event that triggered the current workflow run
        select(.created_at >= $event_start) |

        # Select non-expired artifacts for the same branch and SHA as the current workflow run
        select(contains({expired: false, workflow_run: {head_branch: $branch, head_sha: $sha}})) |

        if $run_id != "" then
          # Select artifacts from the specified workflow run if it is provided
          select((.workflow_run.id | tostring) == $run_id)
        elif $exclude_current_run then
          # Exclude artifacts from the current workflow run if the flag is set
          select(.workflow_run.id != $current_run_id)
        else . end
      ) |

      # Sort by the creation date in ascending order
      sort_by(.created_at) |

      # Prioritise artifacts from the current workflow run
      if contains([{workflow_run: {id: $current_run_id}}]) then
        map(select(.workflow_run.id == $current_run_id))
      else . end |

      # Select the most recent artifact (last in the array)
      .[-1]')
}

echo "Awaiting artifact '$ARTIFACT_NAME' created after $TIMESTAMP for commit $BRANCH@$HEAD_SHA..."

while true; do
  checkRunningWorkflows
  searchArtifact && break
  $awaiting_workflows && sleep 2 && continue
  echo "::error::Artifact '$ARTIFACT_NAME' not found" && exit 1
done

run_id=$(jq .workflow_run.id <<< "$artifact")
echo "run-id=$run_id" >> "$GITHUB_OUTPUT"
echo "artifact-id=$(jq .id <<< "$artifact")" >> "$GITHUB_OUTPUT"

[[ $run_id == "$GH_RUN_ID" ]] && echo "Artifact found in the current workflow run" && exit

declare -A run
eval "run=($(getWorkflowRun))"

echo "Artifact \`$ARTIFACT_NAME\` found in workflow run [**${run[name]} #${run[number]}**: _${run[displayTitle]}_](${run[url]})" |
  tee -a "$GITHUB_STEP_SUMMARY"
