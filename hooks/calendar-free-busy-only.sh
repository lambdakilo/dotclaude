#!/usr/bin/env bash

# Claude Code PreToolUse hook for the Google Calendar connector. It refuses to
# list or read events on a calendar that belongs to another person, since those
# carry titles, attendees and meeting links, and points the session at the
# free/busy lookup instead. The user's own calendar is "primary", and shared
# group, room and holiday calendars have ids under calendar.google.com.

set -u

calendar="$(jq -r '.tool_input.calendarId // empty' 2>/dev/null)" || exit 0
case "$calendar" in
  "" | primary | *calendar.google.com) exit 0 ;;
esac

reason="Events on another person's calendar are off limits. To find a time with \
other people, call the connector's suggest_time, which reads free/busy only. \
For the user's own calendar, pass calendarId primary. When the user needs that \
person's events, they open the calendar themselves."

jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $reason}}'
