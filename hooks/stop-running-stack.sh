#!/usr/bin/env bash

# Claude Code Stop hook. When the turn that is ending ran a command that
# starts a compose stack, and a compose project of this repository or one of
# its worktrees still has containers up, it sends the turn back once with the
# reason, so the stack is stopped and the reply says so. It stops nothing
# itself, and a turn that started nothing passes.
# A turn passes too when stack-held-by-peer.sh records the stack as another
# session's.
# The current turn is read from the transcript, whose format Claude Code does
# not document, so a change there makes this hook quietly pass every turn.

set -u

command -v jq >/dev/null 2>&1 || exit 0
command -v docker >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = false ] || exit 0
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -f "$transcript" ] || exit 0

jq -Rrn '
  [inputs | fromjson? // empty] as $lines
  | ([$lines | to_entries[]
      | select(.value.type == "user" and (.value.isMeta | not)
          and (.value.message.content
               | if type == "string" then true
                 else all(.[]?; .type != "tool_result") end))
      | .key] | last // 0) as $turn
  | $lines[$turn:][]
  | select(.type == "assistant") | .message.content[]?
  | select(.type == "tool_use" and .name == "Bash") | .input.command // empty
' "$transcript" 2>/dev/null |
  grep -Eq '[[:alnum:]_-]+ +start:local|docker(-| +)compose .*up( |$)' || exit 0

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
case "$common_dir" in
  */.git) root="${common_dir%/.git}" ;;
  *) root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")" ;;
esac

projects="$(docker ps --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null |
  awk -F '\t' -v root="$root" '$2 == root || index($2, root "/") == 1 { print $1 }' |
  sort -u | paste -sd ' ' -)"
[ -n "$projects" ] || exit 0
holder="$(cut -f1 "$common_dir/claude-stack-holder" 2>/dev/null)"
[ -z "$holder" ] || [ "$holder" = "$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" ] || exit 0

echo "This turn started a stack and compose project $projects is still up. Stop it with the project's own stop command and say in the reply that it is stopped." >&2
exit 2
