#!/usr/bin/env bash

# Claude Code PostToolUse hook for Bash. After a command that runs git switch,
# git checkout or gh pr checkout in a repository that has submodules, it runs
# git submodule update --init: a switch moves each submodule's pin in the
# index but leaves its work tree where it was, and submodule.recurse skips a
# submodule whose pin is the same on both branches even when its work tree has
# drifted. It hands git submodule status, or the error that stopped the
# update, to the model as context, and prints nothing for any other command.
#
# The repository is the one named by git -C before the switch, else by the
# first cd in the command, else the session's working directory.

set -u

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$command" ] || exit 0

sp='[[:space:]]'
arg='("[^"]*"|[^[:space:];&|()]+)'
printf '%s\n' "$command" |
  grep -Eq "(^|[;&|(])$sp*(git($sp+-C$sp+$arg)?$sp+(switch|checkout)|gh$sp+pr$sp+checkout)($sp|\$)" ||
  exit 0

dir="$(printf '%s\n' "$command" | grep -Eo "git$sp+-C$sp+$arg$sp+(switch|checkout)" | head -n 1 |
  sed -E "s/^git$sp+-C$sp+//; s/$sp+(switch|checkout)\$//")"
[ -n "$dir" ] || dir="$(printf '%s\n' "$command" | grep -Eo "(^|[;&|(])$sp*cd$sp+$arg" | head -n 1 |
  sed -E "s/^[;&|(]?$sp*cd$sp+//")"
dir="${dir#\"}"
dir="${dir%\"}"
case "$dir" in
  "~" | "~/"*) dir="$HOME${dir#"~"}" ;;
esac
base="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
case "$dir" in
  "") dir="$base" ;;
  /*) ;;
  *) dir="$base/$dir" ;;
esac

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$top/.gitmodules" ] || exit 0

ssh_command="${GIT_SSH_COMMAND:-$(git -C "$top" config core.sshCommand 2>/dev/null || echo ssh)}"
if output="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true GIT_SSH_COMMAND="$ssh_command -o BatchMode=yes" \
  git -C "$top" submodule update --init 2>&1)"; then
  context="Ran git submodule update --init in $top after the switch."
else
  context="git submodule update --init failed in $top after the switch, so a submodule work tree may be off its pin:
$output"
fi
context="$context
git submodule status:
$(git -C "$top" submodule status 2>&1)"

jq -n --arg context "$context" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
exit 0
