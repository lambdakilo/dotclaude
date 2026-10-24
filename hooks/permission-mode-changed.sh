#!/usr/bin/env bash

# Claude Code hook for UserPromptSubmit. The permission mode can change between
# prompts with nothing in the context saying so, as a switch from bypass to auto
# mode in the desktop app does, and a session that read its mode earlier goes on
# stating the old one. This keeps the mode of each session's last prompt and,
# when a prompt arrives under another mode, adds both to the context.
# Anything missing lets the prompt through without a word.

set -u
command -v jq >/dev/null 2>&1 || exit 0

session="" mode=""
{
  IFS= read -r session
  IFS= read -r mode
} < <(jq -r '.session_id // "", .permission_mode // ""' 2>/dev/null)
case "$session" in "" | *[^A-Za-z0-9_-]*) exit 0 ;; esac
case "$mode" in "" | *[^A-Za-z]*) exit 0 ;; esac

dir="${TMPDIR:-/tmp}/claude-permission-modes"
mkdir -p "$dir" 2>/dev/null || exit 0
find "$dir" -type f -mtime +7 -delete 2>/dev/null
state="$dir/$session"
previous="$(cat "$state" 2>/dev/null)"
printf '%s\n' "$mode" >"$state" 2>/dev/null

[ -n "$previous" ] && [ "$previous" != "$mode" ] || exit 0
label() { if [ "$1" = default ]; then echo "default (Manual in the app)"; else echo "$1"; fi; }
jq -n --arg from "$(label "$previous")" --arg to "$(label "$mode")" '{hookSpecificOutput: {
  hookEventName: "UserPromptSubmit",
  additionalContext: "The permission mode of this session changed from \($from) to \($to) before this prompt. It is \($to) now, and a mode read earlier in the session no longer holds."
}}'
exit 0
