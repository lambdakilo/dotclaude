#!/usr/bin/env bash

# Claude Code PostToolUse hook for the Slack connector's user search. The search
# lists only the members of the user's own workspace, so a member of another
# organisation who writes in a shared Slack Connect channel is missing from its
# results, although the connector reads that channel's messages. It hands the
# model that fact and where to look instead.

set -u
cat >/dev/null

context="Slack user search lists only the members of the user's own workspace. \
A member of another organisation who writes in a shared Slack Connect channel \
is not in these results, yet the connector reads that channel's messages like \
any other's, with the writer marked external. When the person the user named \
is not here, grep the project's memory for the name and read the shared \
channels it names with slack_read_channel, newest first, before calling the \
message out of reach or asking the user where it is."

jq -n --arg context "$context" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
