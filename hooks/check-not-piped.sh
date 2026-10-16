#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a check (verify, tests, lint,
# typecheck, build, end to end) piped into another command. A pipeline exits
# with the status of its last command, so a failed check piped into tail
# reports as a pass. Quoted strings and heredoc bodies are not looked at, and a
# command that sets pipefail or reads the pipe status goes through.

set -u

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
case "$cmd" in
  *pipefail* | *pipestatus* | *PIPESTATUS*) exit 0 ;;
esac
cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"

runner='(npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?(verify|test|lint|typecheck|check|build|e2e)'
runner+='|(npx|bunx)[[:space:]]+(tsc|playwright|vitest|jest|eslint)'
runner+='|make[[:space:]]+[^|;[:space:]]*(test|verify|check|lint|build)'
runner+='|[[:alnum:]_-]+[[:space:]]+(test|unit|e2e|verify|lint|build):local'
runner+='|(cargo|go)[[:space:]]+(test|build)'
bare='(tsc|vitest|jest|pytest|playwright|eslint)'
piped='[^|;]*\|([^|]|$)'

printf '%s\n' "$cmd" | grep -Eq \
  -e "(^|[;&(]|[[:space:]])($runner)$piped" \
  -e "(^|[;&(])[[:space:]]*$bare$piped" || exit 0

cat >&2 <<'EOF'
Refused: this check is piped into another command, and a pipeline exits with
its last command's status, so a failed check would read as a pass. Send the
output to a file in the scratchpad, print the status, then read the file:

  npm run verify > <scratchpad>/verify.log 2>&1; echo exit=$?
  tail -60 <scratchpad>/verify.log

Or start the command with set -o pipefail.
EOF
exit 2
