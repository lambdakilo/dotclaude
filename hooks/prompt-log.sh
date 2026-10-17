#!/usr/bin/env bash

# Claude Code UserPromptSubmit hook that logs the session's prompts, and the
# reader that prints them for a commit message or a PR body, so the prompts are
# quoted as typed instead of retyped from the conversation. As a hook it prints
# nothing, because whatever a UserPromptSubmit hook prints is added to the
# model's context, and it always exits 0, so it never blocks a prompt.
#
#   prompt-log.sh                              append the prompt in the hook
#                                              input to prompt-log/<session>.jsonl
#   prompt-log.sh print [--commit] [--from n]  print the session's prompts
#
# print numbers every prompt of the session in CLAUDE_CODE_SESSION_ID, or in
# PROMPT_LOG_SESSION when set, as **n.** and > lines for a PR body, or with
# --commit as n. and > lines wrapped at 72 columns. --from n starts at prompt
# n. The log keeps each prompt as it arrived. print drops what the harness
# wraps in tags: reminders, artifact context, peer session messages, subagent
# hand-backs and notifications, and an entry with nothing else in it gets no
# number. A pasted block comes out as [pasted: n lines], URLs and email
# addresses as [pasted: an address], a home path with ~, a temporary path as
# [a temporary path] and a password or token value as [redacted].

set -u

log_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/prompt-log"

if [ "${1:-}" != print ]; then
  umask 077
  input="$(cat)"
  session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
  case "$session" in ""|*[!A-Za-z0-9_-]*) exit 0 ;; esac
  mkdir -p "$log_dir" 2>/dev/null || exit 0
  printf '%s' "$input" \
    | jq -c --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{timestamp: $t, session_id, cwd, prompt}' \
      >>"$log_dir/$session.jsonl" 2>/dev/null
  exit 0
fi
shift

form=pr
from=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --commit) form=commit ;;
    --from) from="${2:-}"; shift ;;
    *) echo "prompt-log: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
case "$from" in ""|*[!0-9]*) echo "prompt-log: --from takes a prompt number" >&2; exit 2 ;; esac

session="${PROMPT_LOG_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
log="$log_dir/$session.jsonl"
if [ -z "$session" ] || [ ! -f "$log" ]; then
  echo "prompt-log: no prompt log for session '$session', set PROMPT_LOG_SESSION" >&2
  exit 1
fi

n=0
jq -j '.prompt
  | gsub("<(?<t>system-reminder|artifact-view-context|cross-session-message|agent-message|task-notification|teammate-message)[\\s>][\\s\\S]*?</\\k<t>\\s*>"; "")
  | gsub("<pasted_content[^>]*>(?<b>[\\s\\S]*?)</pasted_content[^>]*>";
      "[pasted: \(.b | sub("\\A\\s+"; "") | sub("\\s+\\z"; "") | split("\n") | length) lines]")
  | sub("\\A\\s+"; "") | sub("\\s+\\z"; "")
  | select(length > 0)
  | . + "\u0000"' "$log" | while IFS= read -r -d '' prompt; do
  n=$((n + 1))
  [ "$n" -ge "$from" ] || continue
  prompt="$(printf '%s\n' "$prompt" | sed -E \
    -e 's#[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]*[^[:space:].,;:!?)]#[pasted: an address]#g' \
    -e 's#[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^[:space:]]*[^[:space:].,;:!?)]#[pasted: an address]#g' \
    -e 's#[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}#[pasted: an address]#g' \
    -e 's#(/private)?/tmp/claude-[0-9]+/[^[:space:]"]*#[a temporary path]#g' \
    -e 's#/Users/[^/[:space:]"]+#~#g' \
    -e 's#((mysql|mariadb|mysqldump|mysqladmin)[^|;&]*[[:space:]]-p)[^[:space:]]+#\1[redacted]#g' \
    -e 's#((PASSWORD|PASSWD|TOKEN|SECRET|PWD|[Pp]assword|[Pp]asswd|[Tt]oken|[Ss]ecret)=)[^[:space:]]+#\1[redacted]#g')"
  if [ "$form" = commit ]; then
    printf '%s.\n' "$n"
    printf '%s\n' "$prompt" | fold -s -w 70 | sed -e 's/ *$//' -e 's/^/> /' -e 's/^> $/>/'
  else
    printf '**%s.**\n' "$n"
    printf '%s\n' "$prompt" | sed -e 's/^/> /' -e 's/^> $/>/'
  fi
  printf '\n'
done
