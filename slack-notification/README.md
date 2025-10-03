# Slack Notifications

This action posts messages to a Slack channel from workflows.
For example, if a workflow fails a message can be sent to Slack notifying a team of the failure so they can investigate the root cause

## Usage

This action requires an SNS arn, which can be obtained from a stack created using the `build-notifications` template. This will post a message the a Slack channel associated with the arn via Amazon Q Developer in chat applications.

Setting up Build notifications and Chatbots and how they work is beyond the scope of this action. Documentation can be found [here](https://govukverify.atlassian.net/wiki/spaces/PLAT/pages/3377168419/Slack+build+notifications+-+via+AWS+Chatbot)

A SNS ARN is the only information required to be able to post a message to a Slack channel. In this case, a default message is created

### Parameters

- `sns-arn`: Required. The SNS Topic ARN to publish the notification to. This can be obtained as an output from the relevant `build-notification` stack
- `message-title`: The title of the message to send. If omitted, this defaults to the name of the workflow
- `message-description`: The description or body of the message to send. If omitted, this defaults to the name of the workflow and a link to the workflow run
- `status`: Optional status to include in the default message description (e.g., 'Success', 'Failure'). If included, it is inserted into the message description, so the message becomes the name of the workflow, the status and a link to the workflow run. This only applies to the default message. If a custom message is provided in `message-description` the `status` is ignored, though status information can be included in that custom message
- `status-icon`: Optional icon to include with the status in the default message title (e.g., ':white_check_mark:', ':x:'). If included, it is prepended to the message title, so the title becomes the icon and the name of the workflow. This only applies to the default message title. If a custom title is provided in `message-icon` the `status-icon` is ignored, though status an icon can be included in that custom title

## Using actions from this repo in other repos

Use the following syntax in your workflow:

`uses: govuk-one-login/github-actions/slack-notification@{ref}`

The `ref` can be a specific branch, git ref or commit SHA.

### Examples:

#### Default Message

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
```

## ![title](img/default-message.png "Default message")

#### Default Message with Status

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
          status: "FAILED"
```

## ![title](img/default-message-status.png "Default message with status")

#### Default Message with Status and Icon

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
          status: "FAILED"
          status-icon: ":x:"
```

## ![title](img/default-message-status-icon.png "Default message with status icon")

#### Custom Message Title

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
          message-title: "Custom Title"
```

## ![title](img/custom-message-title.png "Custom message title")

#### Custom Message Title and Description

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
          message-title: "Custom Title"
          message-description: "Custom message being sent to Slack from the workflow"
```

## ![title](img/custom-message.png "Custom message title and description")

#### Custom Message Title with Icon and Description

```yaml
jobs:
  job:
    steps:
      - name: Step
        uses: govuk-one-login/github-actions/slack-notification@main
        with:
          sns-arn: arn:aws:sns:eu-west-2:999999999999:my-build-notification-topic
          message-title: ":x: Custom Title"
          message-description: "Custom message being sent to Slack from the workflow"
```

![title](img/custom-message-icon.png "Custom message title with icon and description")
