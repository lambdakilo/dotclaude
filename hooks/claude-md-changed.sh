#!/usr/bin/env bash

# Claude Code hook for SessionStart, UserPromptSubmit and PreToolUse on Bash.
# A session loads CLAUDE.md once, so an edit made from another session while it
# runs stays invisible to it. This keeps a copy of the file per session and,
# once the file differs from that copy, adds the diff to the next prompt, or
# blocks the next commit or pull request command once with the diff on stderr.
# Anything missing lets the prompt or the command through.

set -u

rules="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
[ -f "$rules" ] && command -v jq >/dev/null 2>&1 || exit 0

event="" key="" guarded="" transcript=""
{
  IFS= read -r event
  IFS= read -r key
  IFS= read -r guarded
  IFS= read -r transcript
} < <(jq -r '
  .hook_event_name // "",
  (.session_id // "") + (if (.agent_id // "") == "" then "" else "-" + .agent_id end),
  ((.tool_input.command // "") | test("(^|[^A-Za-z0-9_./-])(git( -[Cc] [^ ]+)* commit|gh pr (create|edit|merge))"))
  , .transcript_path // ""
' 2>/dev/null)
case "$key" in "" | *[^A-Za-z0-9_-]*) exit 0 ;; esac

dir="${TMPDIR:-/tmp}/claude-md-snapshots"
snapshot="$dir/$key"
mkdir -p "$dir" 2>/dev/null || exit 0

case "$event" in
  SessionStart)
    find "$dir" -type f -mtime +7 -delete 2>/dev/null
    cp "$rules" "$snapshot" 2>/dev/null
    exit 0
    ;;
  UserPromptSubmit) ;;
  PreToolUse) [ "$guarded" = true ] || exit 0 ;;
  *) exit 0 ;;
esac

# A subagent, or a session that started before this hook existed, takes its
# first look as the copy it loaded.
[ -f "$snapshot" ] || { cp "$rules" "$snapshot" 2>/dev/null; exit 0; }
cmp -s "$rules" "$snapshot" && exit 0

limit=80
changes="$(diff -U2 "$snapshot" "$rules" | tail -n +3)"
total="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
if [ "$total" -gt "$limit" ]; then
  changes="$(printf '%s\n' "$changes" | head -n "$limit")
[$((total - limit)) more diff lines cut, read the whole file with the Read tool]"
fi
# The stale cache guard may block this prompt and its context with it, so while
# the session is stale the copy stays and the diff comes again with the next one.
if [ "$event" != UserPromptSubmit ] || ! "${0%/*}/stale-cache-guard.sh" --stale "$transcript"; then
  cp "$rules" "$snapshot" 2>/dev/null || exit 0
fi

if [ "$event" = UserPromptSubmit ]; then
  jq -n --arg context "~/.claude/CLAUDE.md changed since this session loaded it. The diff below is in force now:
$changes" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $context}}'
  exit 0
fi
printf '%s\n%s\n' "Blocked once: ~/.claude/CLAUDE.md changed since this session last saw it. The diff below is in force now. Bring the message or body in line with it, then run the command again." "$changes" >&2
exit 2
