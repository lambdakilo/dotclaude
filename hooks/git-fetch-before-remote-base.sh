#!/usr/bin/env bash

# Claude Code PreToolUse hook on Bash. Before a command that branches,
# rebases, merges, hard-resets or adds a worktree from an origin/ or upstream/
# ref, it runs git-fetch-prune.sh and waits for it, so the command starts from
# fresh remote-tracking refs. It skips the fetch when the command fetches or
# pulls itself, or when the repository fetched in the last 2 minutes. A soft
# or mixed reset is left alone: it keeps the tree on hand, so a ref that moved
# under it would turn the new commits into reverts. It prints nothing and
# never blocks.
#
# The repository is the one named by git -C before the command, else by the
# first cd in the command, else the session's working directory.

set -u

input="$(cat)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$command" ] || exit 0

sp='[[:space:]]'
arg='("[^"]*"|[^[:space:];&|()]+)'
git_c="(^|[;&|(])$sp*git($sp+-C$sp+$arg)?$sp+"
subcommands='(switch|checkout|rebase|merge|reset|worktree)'

from_remote_ref() {
  printf '%s\n' "$command" | grep -Eo "$git_c$1($sp[^;&|()]*)?" |
    grep -Eq "$sp[\"']?(origin|upstream)/"
}
from_remote_ref '(switch|checkout|rebase|merge|worktree)' ||
  from_remote_ref "reset$sp[^;&|()]*--hard" ||
  exit 0
printf '%s\n' "$command" | grep -Eq "$git_c(fetch|pull)($sp|\$)" && exit 0

dir="$(printf '%s\n' "$command" | grep -Eo "git$sp+-C$sp+$arg$sp+$subcommands" | head -n 1 |
  sed -E "s/^git$sp+-C$sp+//; s/$sp+$subcommands\$//")"
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
fetch_head="$(git -C "$top" rev-parse --path-format=absolute --git-path FETCH_HEAD 2>/dev/null)"
[ -n "$(find "$fetch_head" -mmin -2 2>/dev/null)" ] && exit 0

CLAUDE_PROJECT_DIR="$top" CLAUDE_GIT_FETCH_INTERVAL_MINUTES=2 \
  "$(dirname "$0")/git-fetch-prune.sh" </dev/null
exit 0
