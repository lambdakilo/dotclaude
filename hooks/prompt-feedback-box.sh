#!/usr/bin/env bash

# Claude Code hook for the desktop app's next-step box, run before every
# mcp__ccd_turn__wrap_up call and on every prompt. A box that asks a question
# ends the turn and takes no text after it, so the closing reply and the
# Prompt feedback section come before it. In a turn a typed prompt opened, it
# refuses such a box once while nothing written in the turn carries a Prompt
# feedback heading. On a prompt that repeats a reply button of the last box,
# it tells Claude that it wrote those words itself, so the section is left out.
# The turn is read from the transcript, whose format Claude Code does not
# document, so a change there makes this hook quietly pass. Claude Code runs
# the hook before the message that holds the call reaches the transcript,
# which it writes from a queue flushed every 100 ms, so the hook waits up to
# 3 seconds for the record of its own call and passes when it never shows.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -f "$transcript" ] || exit 0
box=mcp__ccd_turn__wrap_up

if [ "$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)" = UserPromptSubmit ]; then
  prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"
  grep -F "\"$box\"" "$transcript" 2>/dev/null | jq -Rn -e --arg box "$box" --arg prompt "$prompt" '
    def trimmed: gsub("^\\s+|\\s+$"; "");
    [inputs | fromjson? // empty | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == $box)] | last
    | any(.input.actions[]?; (.message // .label // "") | trimmed == ($prompt | trimmed))
  ' >/dev/null 2>&1 || exit 0
  jq -n '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
    "This prompt repeats a reply button of your last next-step box, words you wrote, so leave the Prompt feedback section out."}}'
  exit 0
fi

[ "$(printf '%s' "$input" | jq -r '.tool_input.ask // "" | length > 0' 2>/dev/null)" = true ] || exit 0
reason="A question in the next-step box ends the turn and takes no text after it. \
Write the closing reply first: the answer, any draft the question asks about, and \
the Prompt feedback section. Then call wrap_up again."

id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null)"
[ -n "$id" ] || exit 0
waited=0
until grep -qF "\"$id\"" "$transcript" 2>/dev/null; do
  [ "$waited" -lt 30 ] || exit 0
  sleep 0.1
  waited=$((waited + 1))
done

jq -Rn -e --arg box "$box" --arg marker "${reason%%.*}" '
  def text: if type == "string" then . else [.[]? | select(.type == "text") | .text] | join("\n") end;
  def trimmed: gsub("^\\s+|\\s+$"; "");
  [inputs | fromjson? // empty] as $lines
  | ([$lines | to_entries[] | select(.value.type == "user" and .value.origin != null) | .key]
     | last) as $turn
  | ($lines[$turn].message.content | text | trimmed) as $prompt
  | $lines[$turn].origin.kind == "human"
    and ([$lines[:$turn][] | select(.type == "assistant") | .message.content[]?
          | select(.type == "tool_use" and .name == $box)] | last
         | all(.input.actions[]?; (.message // .label // "") | trimmed != $prompt))
    and all($lines[$turn:][] | select(.type == "assistant") | .message.content[]?
            | select(.type == "text") | .text; test("prompt feedback"; "i") | not)
    and all($lines[$turn:][] | select(.type == "user") | .message.content | tostring;
            contains($marker) | not)
' "$transcript" >/dev/null 2>&1 || exit 0

jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  permissionDecision: "deny", permissionDecisionReason: $reason}}'
