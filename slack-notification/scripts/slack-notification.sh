#!/usr/bin/env bash
set -euo pipefail

: "${SNS_ARN:?}" # The SNS Topic ARN (required)
STATUS="${STATUS:-}"
STATUS_ICON="${STATUS_ICON:-}"
MESSAGE_TITLE="${MESSAGE_TITLE:-"$STATUS_ICON$GITHUB_WORKFLOW"}"
MESSAGE_DESCRIPTION="${MESSAGE_DESCRIPTION:-"$GITHUB_WORKFLOW $STATUS - $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"}"
MESSAGE_PAYLOAD=$(
  jq -c . << EOF
{
  "version": 1.0,
  "source": "custom",
  "content": {
    "textType": "client-markdown",
    "title": "$MESSAGE_TITLE",
    "description": "$MESSAGE_DESCRIPTION"
  },
  "metadata": {
    "enableCustomActions": false
  }
}
EOF
)
aws sns publish \
  --topic-arn "$SNS_ARN" \
  --message "${MESSAGE_PAYLOAD}"
