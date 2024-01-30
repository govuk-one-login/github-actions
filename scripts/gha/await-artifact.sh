# Wait for an artifact with the given name to be uploaded by any workflow run in the repository
# with the same branch and SHA as the event that triggered the current action (unless overridden by env vars).
# Returns the ID of the workflow run hosting the desired artifact if found.
set -eu

: "${RUN_ID:-}"                   # Search for the artifact in the specified workflow run, otherwise search in all runs
: "${BRANCH:-}"                   # Search for an artifact uploaded for the specified branch
: "${HEAD_SHA:-}"                 # Search for an artifact uploaded for the specified SHA
: "${TIMESTAMP:-}"                # Search for an artifact uploaded after the specified timestamp
: "${GITHUB_TOKEN}"               # The token to authenticate to the GitHub API
: "${ARTIFACT_NAME}"              # Find an artifact with the specified name
: "${EXCLUDE_CURRENT_RUN:=false}" # Exclude artifacts from the workflow running this script

: "${BRANCH:=${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}}"
: "${HEAD_SHA:=$(jq --raw-output '.pull_request.head.sha // .head_commit.id' < "$GITHUB_EVENT_PATH")}"
: "${TIMESTAMP:=$(jq --raw-output '.pull_request.updated_at // .head_commit.timestamp' < "$GITHUB_EVENT_PATH")}"

function getArtifacts() {
  gh api "/repos/$GITHUB_REPOSITORY/actions/artifacts?name=$ARTIFACT_NAME"
}

function getWorkflowRun() {
  gh api "/repos/$GITHUB_REPOSITORY/actions/runs/$run_id"
}

function getWorkflowRuns() {
  # Get all workflow runs in the repo for the same user, branch and SHA that were triggered by the same event and started after it occurred
  gh api "/repos/$GITHUB_REPOSITORY/actions/runs?actor=$GITHUB_ACTOR&branch=$BRANCH&created=>=$TIMESTAMP&head_sha=$HEAD_SHA&event=$GITHUB_EVENT_NAME"
}

function checkRunningWorkflows() {
  [[ $(getWorkflowRuns |
    jq --argjson id "$GITHUB_RUN_ID" '.workflow_runs[] | select(.id != $id and .status != "completed")') ]] &&
    awaiting_workflows=true || awaiting_workflows=false
}

function searchArtifact() {
  artifact=$(getArtifacts |
    jq --exit-status \
      --arg branch "$BRANCH" --arg sha "$HEAD_SHA" --arg event_start "$TIMESTAMP" --arg run_id "${RUN_ID:-}" \
      --argjson current_run_id "$GITHUB_RUN_ID" --argjson exclude_current_run $EXCLUDE_CURRENT_RUN \
      '.artifacts |

      # Filter artifacts
      map(
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

[[ $run_id == "$GITHUB_RUN_ID" ]] && echo "Artifact found in the current workflow run" && exit

workflow_run=$(getWorkflowRun)
workflow_name=$(jq --raw-output .name <<< "$workflow_run")
title=$(jq --raw-output .display_title <<< "$workflow_run")
run_url=$(jq --raw-output .html_url <<< "$workflow_run")
run_number=$(jq .run_number <<< "$workflow_run")

echo "Artifact \`$ARTIFACT_NAME\` found in workflow run [**$workflow_name #$run_number**: _${title}_]($run_url)" |
  tee "$GITHUB_STEP_SUMMARY"
