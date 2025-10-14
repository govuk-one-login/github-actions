#!/usr/bin/env bash
set -euo pipefail

: "${SNS_TOPIC_ARN:?}" # The SNS Topic ARN (required)

: "${WORKFLOW_MESSAGE:="false"}"
: "${STATUS:=}"
: "${STATUS_ICON:=}"

if [[ "${WORKFLOW_MESSAGE}" == "true" ]]; then
  MESSAGE_DESCRIPTION="${MESSAGE_DESCRIPTION:=${GITHUB_WORKFLOW} - ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}${STATUS:+ ${STATUS}}}"
else
  : "${MESSAGE_DESCRIPTION:?parameter null or not set}"
fi
MESSAGE_TITLE=${MESSAGE_TITLE:=$GITHUB_WORKFLOW}

if [[ -z "${STATUS_ICON}" ]]; then
  if [[ "$(echo "${STATUS}" | tr '[:upper:]' '[:lower:]')" == "failed" ]]; then
    STATUS_ICON="❌"
  elif [[ "$(echo "${STATUS}" | tr '[:upper:]' '[:lower:]')" == "succeeded" ]]; then
    STATUS_ICON="✅"
  fi
fi

message_payload=$(
  jq -c . << EOF
{
  "version": 1.0,
  "source": "custom",
  "content": {
    "textType": "client-markdown",
    "title": "${STATUS_ICON:+ ${STATUS_ICON}}$MESSAGE_TITLE",
    "description": "$MESSAGE_DESCRIPTION"
  },
  "metadata": {
    "enableCustomActions": false
  }
}
EOF
)

aws sns publish \
  --topic-arn "$SNS_TOPIC_ARN" \
  --message "${message_payload}"
