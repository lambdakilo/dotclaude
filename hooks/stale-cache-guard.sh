#!/usr/bin/env bash

# Claude Code hook for UserPromptSubmit. The main conversation's prompt cache
# lasts an hour and idle compaction runs only in terminal sessions, so the first
# prompt after a longer break into a large conversation writes all of it to the
# cache again. This blocks that prompt once with the size and the idle time, and
# sending it again goes through. A prompt that starts with a slash passes, and so
# does one that starts with a tag, which is how subagent reports, notifications
# and messages from other sessions arrive.
#
#   stale-cache-guard.sh                       the hook, with its input on stdin
#   stale-cache-guard.sh --stale <transcript>  exit 0 when the last turn is large
#                                              and older than the cache

set -u
command -v jq >/dev/null 2>&1 || exit 0

min_tokens=200000
min_idle=3600

tokens="" idle="" stamp=""
stale() {
  [ -f "$1" ] || return 1
  read -r tokens idle stamp < <(tail -n 400 "$1" | jq -rRn '
    [inputs | fromjson? | select(
        (.type == "assistant" and .message.usage != null and .message.model != "<synthetic>")
        or (.type == "system" and .subtype == "compact_boundary"))]
    | last // empty
    | select(.type == "assistant")
    | .message.usage as $u
    | (.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601) as $t
    | "\(($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) \(now - $t | floor) \($t)"' 2>/dev/null)
  [ -n "$stamp" ] && [ "$tokens" -ge "$min_tokens" ] && [ "$idle" -ge "$min_idle" ]
}

if [ "${1:-}" = --stale ]; then
  stale "${2:-}"
  exit
fi

session="" agent="" transcript="" first=""
{
  IFS= read -r session
  IFS= read -r agent
  IFS= read -r transcript
  IFS= read -r first
} < <(jq -r '.session_id // "", .agent_id // "", .transcript_path // "",
  ((.prompt // "") | sub("\\A\\s+"; "") | .[0:1])' 2>/dev/null)
case "$session" in "" | *[!A-Za-z0-9_-]*) exit 0 ;; esac
[ -z "$agent" ] || exit 0
case "$first" in "" | / | "<") exit 0 ;; esac
stale "$transcript" || exit 0

dir="${TMPDIR:-/tmp}/stale-cache-guard"
marker="$dir/$session-$stamp"
[ -e "$marker" ] && exit 0
mkdir -p "$dir" 2>/dev/null && touch "$marker" 2>/dev/null || exit 0
find "$dir" -type f -mtime +7 -delete 2>/dev/null

echo "Blocked once: this session holds $((tokens / 1000))k tokens and has been idle $((idle / 3600)) h, so its prompt cache has expired and this prompt would write all of it to the cache again. Run /compact first, or start a new session with a short brief, or send the prompt again to go on here." >&2
exit 2
