#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. A compose stack with fixed container
# names is one per machine, shared by every session of a repository and its
# worktrees. A start notes in the git directory which session holds the
# stack. While the holder's containers are up, or its start is under 15
# minutes old, and its transcript changed in the last 15 minutes, this hook
# refuses another session's start, restart, stop or removal. Containers count
# as the repository's when their compose project is named like it or like the
# command's COMPOSE_PROJECT_NAME, or their working directory is in it or in
# one of its worktrees. That is a heuristic, and quoted strings and heredoc
# bodies are not looked at.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
raw="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$raw" ] || exit 0

cmd="${raw%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
local_cmd='[[:alnum:]_-]+[[:space:]]+'
compose='docker(-|[[:space:]]+)compose([[:space:]][^;&|]*)?[[:space:]]'
if printf '%s\n' "$cmd" | grep -Eq \
  -e "${local_cmd}(start|restart|init)(:[[:alnum:]_-]+)*:local" \
  -e "${compose}(up|restart)([[:space:]]|$)"; then
  kind=start
elif printf '%s\n' "$cmd" | grep -Eq \
  -e "${local_cmd}(stop|down)(:[[:alnum:]_-]+)*:local" \
  -e "${compose}(down|rm|stop|kill)([[:space:]]|$)"; then
  kind=stop
else
  exit 0
fi

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$session" ] || exit 0

repo="${CLAUDE_PROJECT_DIR:-$PWD}"
common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
[ -n "$common_dir" ] || exit 0
case "$common_dir" in
  */.git) root="${common_dir%/.git}" ;;
  *) root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")" ;;
esac
marker="$common_dir/claude-stack-holder"

holder=""
holder_transcript=""
[ -f "$marker" ] && IFS=$'\t' read -r holder holder_transcript < "$marker"

if [ -n "$holder" ] && [ "$holder" != "$session" ] &&
  [ -n "$(find "$holder_transcript" -mmin -15 2>/dev/null)" ]; then
  held="$(find "$marker" -mmin -15 2>/dev/null)"
  if [ -z "$held" ] && command -v docker >/dev/null 2>&1; then
    project="$(printf '%s\n' "$raw" | grep -oE 'COMPOSE_PROJECT_NAME=[^[:space:];&|]+' |
      head -n 1 | cut -d= -f2 | tr -d "\"'")"
    worktrees="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
    held="$(docker ps --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null |
      ROOT="$root" PROJECT="$project" WORKTREES="$worktrees" awk -F '\t' '
        BEGIN { n = split(ENVIRON["ROOT"] "\n" ENVIRON["WORKTREES"], dirs, "\n")
                name = ENVIRON["ROOT"]; sub(/.*\//, "", name) }
        $1 != "" && ($1 == name || $1 == ENVIRON["PROJECT"]) { print $1; exit }
        { for (i = 1; i <= n; i++)
            if (dirs[i] != "" && ($2 == dirs[i] || index($2, dirs[i] "/") == 1)) { print $1; exit } }')"
  fi
  if [ -n "$held" ]; then
    cat >&2 <<EOF
Refused: session $holder started this repository's compose stack, its
containers are up or starting, and that session is still active. Starting,
restarting, stopping or removing them now breaks whatever it runs on them.
Ask that session with SendMessage to tell you when its stack is down
(ListAgents shows the sessions of this repository), run what needs no stack
meanwhile, and run this again once its containers are down. A notice that you
are taking the stack is not an ask, and a send result saying the message is
not yet read is no answer. When ListAgents shows no such session, ask the user.
EOF
    exit 2
  fi
fi

case "$kind" in
  start) { printf '%s\t%s\n' "$session" "$transcript" > "$marker"; } 2>/dev/null ;;
  stop) rm -f "$marker" ;;
esac
exit 0
