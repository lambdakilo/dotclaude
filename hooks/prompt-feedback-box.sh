#!/usr/bin/env bash

# Claude Code hook for the Prompt feedback section, run when a turn ends and
# on every prompt. In a turn a typed prompt opened, it sends the turn back
# once while the turn's last message has no Prompt feedback heading, so the
# section ends the closing reply, which in the desktop app comes right after
# the next-step box. On a prompt that repeats a reply button of the last box,
# it tells Claude that it wrote those words itself, so the section is left out.
# The turn is read from the transcript, whose format Claude Code does not
# document, so a change there makes this hook quietly pass. The last message
# comes from last_assistant_message, since Claude Code writes the transcript
# from a queue and may not have written that message yet; only when the input
# lacks the field is the turn's last text read from the transcript.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -f "$transcript" ] || exit 0
box=mcp__ccd_turn__wrap_up
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)"

if [ "$event" = UserPromptSubmit ]; then
  prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"
  grep -F "\"$box\"" "$transcript" 2>/dev/null | jq -Rn -e --arg box "$box" --arg prompt "$prompt" '
    def trimmed: gsub("^\\s+|\\s+$"; "");
    def bare: gsub("<(?<t>system-reminder)[\\s>][\\s\\S]*?</\\k<t>\\s*>"; "") | trimmed;
    [inputs | fromjson? // empty | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == $box)] | last
    | any(.input.actions[]? | .label, .message | strings; trimmed == ($prompt | bare))
  ' >/dev/null 2>&1 || exit 0
  jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
    "This prompt repeats a reply button of your last next-step box, words you wrote, so leave the Prompt feedback section out."}}'
  exit 0
fi

[ "$event" = Stop ] || exit 0
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = false ] || exit 0
last="$(printf '%s' "$input" | jq -c 'if has("last_assistant_message") then .last_assistant_message // "" else null end' 2>/dev/null)"
[ -n "$last" ] || exit 0

jq -Rn -e --arg box "$box" --argjson last "$last" '
  def text: if type == "string" then . else [.[]? | select(.type == "text") | .text] | join("\n") end;
  def trimmed: gsub("^\\s+|\\s+$"; "");
  def bare: gsub("<(?<t>system-reminder)[\\s>][\\s\\S]*?</\\k<t>\\s*>"; "") | trimmed;
  [inputs | fromjson? // empty] as $lines
  | ([$lines | to_entries[] | select(.value.type == "user" and .value.origin != null) | .key]
     | last) as $turn
  | ($lines[$turn].message.content | text | bare) as $prompt
  | $lines[$turn].origin.kind == "human"
    and ([$lines[:$turn][] | select(.type == "assistant") | .message.content[]?
          | select(.type == "tool_use" and .name == $box)] | last
         | all(.input.actions[]? | .label, .message | strings; trimmed != $prompt))
    and ($last // ([$lines[$turn:][] | select(.type == "assistant") | .message.content[]?
                    | select(.type == "text") | .text] | last // "")
         | test("prompt feedback"; "i") | not)
' "$transcript" >/dev/null 2>&1 || exit 0

echo "This turn answered a typed prompt and its last message has no Prompt feedback section. \
Write the section now as the turn's last message, without calling wrap_up again. When the \
closing reply after the next-step box only pointed back to text above it, or left out the \
answer or the steps still to do, put those in that message first." >&2
exit 2
