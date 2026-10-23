#!/usr/bin/env bash

# Claude Code Stop hook. When the turn that is ending ran a command that
# starts a compose stack, and a compose project of this repository or one of
# its worktrees still has containers up, it sends the turn back once with the
# reason, so the stack is stopped and the reply says so. It stops nothing
# itself, and a turn that started nothing passes.
# A turn passes too when stack-held-by-peer.sh records the stack as another
# session's. That hook notes each start of a session in the git directory, and
# this hook reads and removes the note when the session's turn ends.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v docker >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)"
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
case "$session" in ""|*[!A-Za-z0-9_-]*) exit 0 ;; esac

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
started="$common_dir/claude-stack-started-$session"
[ -n "$common_dir" ] && [ -f "$started" ] || exit 0
rm -f "$started"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = false ] || exit 0

case "$common_dir" in
  */.git) root="${common_dir%/.git}" ;;
  *) root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")" ;;
esac

projects="$(docker ps --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null |
  awk -F '\t' -v root="$root" '$2 == root || index($2, root "/") == 1 { print $1 }' |
  sort -u | paste -sd ' ' -)"
[ -n "$projects" ] || exit 0
holder="$(cut -f1 "$common_dir/claude-stack-holder" 2>/dev/null)"
[ -z "$holder" ] || [ "$holder" = "$session" ] || exit 0

echo "This turn started a stack and compose project $projects is still up. Stop it with the project's own stop command and say in the reply that it is stopped." >&2
exit 2
