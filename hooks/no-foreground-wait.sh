#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a foreground until, while or
# for loop with a sleep in it that polls the output file of a background job,
# tasks/<id>.output, named in the loop or through a variable set to it. Until
# such a loop returns, every message the user types waits unread, and when the
# job fails before printing the line the loop looks for, the loop sits out its
# whole timeout. A call with run_in_background, or with a timeout of 60 seconds
# or less, goes through. Heredoc bodies are not looked at, nor quoted strings
# for the loop words.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
background="$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)"
[ "$background" = true ] && exit 0
timeout="$(printf '%s' "$input" | jq -r '.tool_input.timeout // 120000 | floor' 2>/dev/null)"
case "$timeout" in '' | *[!0-9]*) timeout=120000 ;; esac
[ "$timeout" -le 60000 ] && exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="${cmd//$'\n'/;}"
task='tasks/[[:alnum:]_-]+\.output'
printf '%s\n' "$cmd" | grep -Eq "$task" || exit 0

word='(^|[;&|(){}!]|[[:space:]])'
end='([^[:alnum:]_]|$)'
bare="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
printf '%s\n' "$bare" | grep -Eq "${word}(until|while|for)[[:space:]]" || exit 0
printf '%s\n' "$bare" | grep -Eq "${word}do$end" || exit 0
printf '%s\n' "$bare" | grep -Eq "${word}sleep[[:space:]]" || exit 0

refs="$task"
for name in $(printf '%s\n' "$cmd" | grep -oE "[[:alpha:]_][[:alnum:]_]*=[\"']?[^;&|[:space:]]*$task" | sed 's/=.*//'); do
  refs+="|\\\$\\{?$name\\}?$end"
done
printf '%s\n' "$cmd" | grep -Eq "${word}(until|while|for)[[:space:]].*($refs).*${word}done$end" || exit 0

cat >&2 <<'MSG'
Refused by ~/.claude/hooks/no-foreground-wait.sh: this loop polls a background
job's output file in the foreground. Until it returns, every message the user
types waits unread, and when the job fails before printing the line the loop
looks for, the loop sits out its whole timeout and then goes on running in the
background. The job sends a notice when it exits: do other work or end the
turn until it comes. To act on a line the job prints before it exits, such as
a ready line, run the same until-loop with the Monitor tool.
MSG
exit 2
