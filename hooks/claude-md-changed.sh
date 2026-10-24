#!/usr/bin/env bash

# Claude Code hook for SessionStart, UserPromptSubmit and PreToolUse on Bash.
# A session reads CLAUDE.md and the pull-requests skill once, so an edit made
# from another session while it runs stays invisible to it. This keeps a copy
# of each file per session and, once one differs from its copy, adds the diff
# to the next prompt, or blocks the next command that depends on it once with
# the diff on stderr: a commit or pull request command for CLAUDE.md, a pull
# request command for the skill. Anything missing lets the prompt or the
# command through.

set -u

config="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
command -v jq >/dev/null 2>&1 || exit 0

event="" key="" pr="" guarded=""
{
  IFS= read -r event
  IFS= read -r key
  IFS= read -r pr
  IFS= read -r guarded
} < <(jq -r '
  .hook_event_name // "",
  (.session_id // "") + (if (.agent_id // "") == "" then "" else "-" + .agent_id end),
  ((.tool_input.command // "") | test("(^|[^A-Za-z0-9_./-])gh pr (create|edit|merge)")),
  ((.tool_input.command // "") | test("(^|[^A-Za-z0-9_./-])(git( -[Cc] [^ ]+)* commit|gh pr (create|edit|merge))"))
' 2>/dev/null)
case "$key" in "" | *[^A-Za-z0-9_-]*) exit 0 ;; esac

dir="${TMPDIR:-/tmp}/claude-md-snapshots"
mkdir -p "$dir" 2>/dev/null || exit 0

case "$event" in
  SessionStart) find "$dir" -type f -mtime +7 -delete 2>/dev/null ;;
  UserPromptSubmit) ;;
  PreToolUse) [ "$guarded" = true ] || exit 0 ;;
  *) exit 0 ;;
esac

limit=80 notes=""
check() {
  local name="$1" file="$2" snapshot="$dir/$key$3" needed="$4" changes total
  [ -f "$file" ] || return 0
  if [ "$event" = SessionStart ]; then
    cp "$file" "$snapshot" 2>/dev/null
    return 0
  fi
  [ "$event" = PreToolUse ] && [ "$needed" != true ] && return 0
  # A subagent, or a session that started before this hook watched the file,
  # takes its first look as the copy it loaded.
  [ -f "$snapshot" ] || { cp "$file" "$snapshot" 2>/dev/null; return 0; }
  cmp -s "$file" "$snapshot" && return 0
  changes="$(diff -U2 "$snapshot" "$file" | tail -n +3)"
  total="$(printf '%s\n' "$changes" | wc -l | tr -d ' ')"
  if [ "$total" -gt "$limit" ]; then
    changes="$(printf '%s\n' "$changes" | head -n "$limit")
[$((total - limit)) more diff lines cut, read the whole file with the Read tool]"
  fi
  cp "$file" "$snapshot" 2>/dev/null || return 0
  notes="${notes:+$notes

}$name changed since this session last saw it. The diff below is in force now:
$changes"
}

check "~/.claude/CLAUDE.md" "$config/CLAUDE.md" "" "$guarded"
check "~/.claude/skills/pull-requests/SKILL.md" "$config/skills/pull-requests/SKILL.md" ".pull-requests" "$pr"
[ -n "$notes" ] || exit 0

if [ "$event" = UserPromptSubmit ]; then
  jq -n --arg context "$notes" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $context}}'
  exit 0
fi
printf '%s\n%s\n' "Blocked once. Bring the message or body in line with the diff below, then run the command again." "$notes" >&2
exit 2
