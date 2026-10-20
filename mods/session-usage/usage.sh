#!/usr/bin/env bash

# Prints the status line of the session-usage mod: how full the context window
# is, the tokens the session has processed and what they would cost at the
# first-party API list prices, and until when the prompt cache stays warm. The
# transcript repeats a response's usage on every streamed block, so each
# response id counts once. A model missing from the price table adds tokens but
# no cost, and the line says so.
#
#   usage.sh <session id>   the session's transcript under projects/
#   usage.sh <transcript>   a transcript file

set -u
command -v jq >/dev/null 2>&1 || exit 0

transcript=${1:-}
if [ -n "$transcript" ] && [ ! -f "$transcript" ]; then
  for f in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl; do
    [ -f "$f" ] && transcript=$f
  done
fi
[ -f "$transcript" ] || exit 0

files=("$transcript")
for f in "${transcript%.jsonl}"/subagents/*.jsonl; do
  [ -f "$f" ] && files+=("$f")
done

# Dollars per million tokens: input, output, cache read, cache write for the
# 5-minute and the 1-hour cache. Writes cost 1.25 and 2 times input.
read -r ctx window tokens cost unpriced warm < <(jq -nrR --arg main "$transcript" '
  def prices: {
    "claude-fable-5-1":  [10, 50, 0.25, 12.5, 20],
    "claude-mythos-5-1": [10, 50, 0.25, 12.5, 20],
    "claude-fable-5":    [10, 50, 1, 12.5, 20],
    "claude-opus-5-5":   [4, 20, 0.2, 5, 8],
    "claude-opus-5":     [5, 25, 0.5, 6.25, 10],
    "claude-opus-4-8":   [5, 25, 0.5, 6.25, 10],
    "claude-sonnet-5-5": [2, 10, 0.2, 2.5, 4],
    "claude-sonnet-5":   [2, 10, 0.2, 2.5, 4],
    "claude-haiku-5-5":  [0.1, 0.5, 0.01, 0.125, 0.2],
    "claude-haiku-4-5":  [1, 5, 0.1, 1.25, 2]
  };
  def n: . // 0;
  def all_in: (.input_tokens | n) + (.cache_creation_input_tokens | n)
    + (.cache_read_input_tokens | n) + (.output_tokens | n);
  [inputs | fromjson? | select(.type == "assistant" and .message.usage != null
      and .message.model != "<synthetic>" and .message.id != null)
    | {id: .message.id, model: .message.model, u: .message.usage,
       at: (.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601),
       main: (input_filename == $main)}]
  | group_by(.id)
  | map({model: .[0].model, u: .[-1].u, at: (map(.at) | min), main: .[0].main})
  | select(length > 0)
  | (map(select(.main)) | max_by(.at)) as $last
  | (map(.u | all_in) | add) as $tokens
  | (map(prices[.model] as $p | .u as $u
      | if $p == null then 0 else
          (($u.input_tokens | n) * $p[0] + ($u.output_tokens | n) * $p[1]
           + ($u.cache_read_input_tokens | n) * $p[2]
           + (if $u.cache_creation == null then ($u.cache_creation_input_tokens | n)
              else ($u.cache_creation.ephemeral_5m_input_tokens | n) end) * $p[3]
           + ($u.cache_creation.ephemeral_1h_input_tokens | n) * $p[4]) / 1000000
        end) | add) as $cost
  | (map(select(prices[.model] == null)) | length) as $unpriced
  | (if any(.[]; .main and (.u.cache_creation.ephemeral_1h_input_tokens | n) > 0)
     then 3600 else 300 end) as $ttl
  | ($last.model | if test("haiku-4|claude-3") then 200000 else 1000000 end) as $window
  | "\($last.u | all_in) \($window) \($tokens) \($cost) \($unpriced) \($last.at + $ttl | floor)"
' "${files[@]}" 2>/dev/null)
[ -n "${warm:-}" ] || exit 0

human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) { s = sprintf("%.1f", n / 1000000); sub(/\.0$/, "", s); printf "%sM", s }
    else if (n >= 1000) printf "%dk", n / 1000
    else printf "%d", n }'
}
clock=$(date -r "$warm" +%H:%M 2>/dev/null || date -d "@$warm" +%H:%M 2>/dev/null)
percent=$(awk -v c="$ctx" -v w="$window" 'BEGIN { printf "%d", c * 100 / w }')
dollars=$(awk -v d="$cost" 'BEGIN { printf "%.2f", d }')
[ "$unpriced" -gt 0 ] && dollars="$dollars ($unpriced unpriced)"

echo "$percent% context, $(human "$tokens") tokens, \$$dollars, cache until $clock"
