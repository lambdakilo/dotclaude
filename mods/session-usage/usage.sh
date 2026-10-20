#!/usr/bin/env bash

# Prints the status line of the session-usage mod: how full the context window
# is, the tokens the session has processed and what they would cost at the
# first-party API list prices, an estimate of the energy the responses took and
# the CO2e it emitted, and until when the prompt cache stays warm. The
# transcript repeats a response's usage on every streamed block, so each
# response id counts once. A model missing from the price table adds tokens but
# no cost, and the line says so.
#
#   usage.sh <session id>   the session's transcript under projects/
#   usage.sh <transcript>   a transcript file
#   usage.sh --run <folder> the tokens, cost and energy of every transcript
#                           under the folder, such as a workflow run's, by kind
#                           and model

set -u
command -v jq >/dev/null 2>&1 || exit 0

# Dollars per million tokens: input, output, cache read, cache write for the
# 5-minute and the 1-hour cache. Writes cost 1.25 and 2 times input.
common='
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
  def secs: (.[0:19] + "Z" | fromdateiso8601) + ((.[20:23] | tonumber?) // 0) / 1000;
  def all_in: (.input_tokens | n) + (.cache_creation_input_tokens | n)
    + (.cache_read_input_tokens | n) + (.output_tokens | n);
  def cost($p): .u as $u
    | if $p == null then 0 else
        (($u.input_tokens | n) * $p[0] + ($u.output_tokens | n) * $p[1]
         + ($u.cache_read_input_tokens | n) * $p[2]
         + (if $u.cache_creation == null then ($u.cache_creation_input_tokens | n)
            else ($u.cache_creation.ephemeral_5m_input_tokens | n) end) * $p[3]
         + ($u.cache_creation.ephemeral_1h_input_tokens | n) * $p[4]) / 1000000
      end;
  def responses($main): reduce (inputs | fromjson? | select(.timestamp != null)) as $e ({seen: {}, r: []};
      (if $e.uuid != null then .seen[$e.uuid] = ($e.timestamp | secs) else . end)
      | if $e.type == "assistant" and $e.message.usage != null
          and $e.message.model != "<synthetic>" and $e.message.id != null
        then .r += [{id: $e.message.id, model: $e.message.model, u: $e.message.usage,
          at: ($e.timestamp | secs), parent: $e.parentUuid, main: (input_filename == $main)}]
        else . end)
    | .seen as $seen
    | .r | group_by(.id)
    | map(min_by(.at) as $first
      | {model: .[0].model, u: .[-1].u, at: $first.at, main: .[0].main,
         busy: ([(map(.at) | max) - ($seen[$first.parent // empty] // $first.at), 0] | max)});

  # Energy: the seconds from the entry a response answers to its last block,
  # times the share of one request in an 8-GPU H100 node as "How Hungry is AI?"
  # (arXiv 2505.09598) models a flagship model: 8 requests to a batch, the GPUs
  # (8 x 700 W) at 45-60% of their draw, the rest of the 10.2 kW node at half,
  # and a PUE of 1.14 (AWS), about 0.75 kW. Grams of CO2e per kWh: the Ember
  # 2025 grid average (Our World in Data), the US for inference_geo "us", else
  # the world, since "global" may run anywhere.
  def kw: (5.6 * 0.525 + 4.6 * 0.5) / 8 * 1.14;
  def kwh: map(.busy * kw / 3600) | add // 0;
  def grams: map(.busy * kw / 3600 * (if .u.inference_geo == "us" then 384.4 else 458.3 end)) | add // 0;'

human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) { s = sprintf("%.1f", n / 1000000); sub(/\.0$/, "", s); printf "%sM", s }
    else if (n >= 1000) printf "%dk", n / 1000
    else printf "%d", n }'
}

energy() {
  awk -v k="$1" -v g="$2" 'BEGIN { printf(k < 0.1 ? "~%.3f kWh, ~%d g CO2e" : "~%.2f kWh, ~%d g CO2e", k, g + 0.5) }'
}

if [ "${1:-}" = --run ]; then
  [ -d "${2:-}" ] || { echo "usage.sh --run <folder>" >&2; exit 2; }
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(find "$2" -name '*.jsonl' -type f 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || { echo "no transcripts under $2" >&2; exit 1; }
  jq -nrR "$common"'
    responses("")
    | (map(.u | all_in) | add // 0) as $tokens
    | (map(cost(prices[.model])) | add // 0) as $cost
    | (map(select(prices[.model] == null)) | length) as $unpriced
    | (map(.u) | {input: (map(.input_tokens | n) | add // 0),
        write: (map(.cache_creation_input_tokens | n) | add // 0),
        read: (map(.cache_read_input_tokens | n) | add // 0),
        output: (map(.output_tokens | n) | add // 0)}) as $k
    | (group_by(.model) | map(.[0].model as $m | "\($m) \(map(.u | all_in) | add) \(map(cost(prices[$m])) | add)")) as $models
    | "\($tokens) \($cost) \($unpriced) \(kwh) \(grams) \($k.input) \($k.write) \($k.read) \($k.output)", $models[]
  ' "${files[@]}" 2>/dev/null | {
    read -r tokens cost unpriced kwh grams input write read output || exit 1
    note=""
    [ "$unpriced" -gt 0 ] && note=" ($unpriced responses from models without a price)"
    printf '%s tokens, $%.2f at API list prices%s, %s\n' "$(human "$tokens")" "$cost" "$note" "$(energy "$kwh" "$grams")"
    printf '  input %s, cache write %s, cache read %s, output %s\n' "$(human "$input")" "$(human "$write")" "$(human "$read")" "$(human "$output")"
    while read -r model mtokens mcost; do
      printf '  %s: %s tokens, $%.2f\n' "$model" "$(human "$mtokens")" "$mcost"
    done
  }
  exit 0
fi

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

read -r ctx window tokens cost unpriced kwh grams warm < <(jq -nrR --arg main "$transcript" "$common"'
  responses($main)
  | select(length > 0)
  | (map(select(.main)) | max_by(.at)) as $last
  | (map(.u | all_in) | add) as $tokens
  | (map(cost(prices[.model])) | add) as $cost
  | (map(select(prices[.model] == null)) | length) as $unpriced
  | (if any(.[]; .main and (.u.cache_creation.ephemeral_1h_input_tokens | n) > 0)
     then 3600 else 300 end) as $ttl
  | ($last.model | if test("haiku-4|claude-3") then 200000 else 1000000 end) as $window
  | "\($last.u | all_in) \($window) \($tokens) \($cost) \($unpriced) \(kwh) \(grams) \($last.at + $ttl | floor)"
' "${files[@]}" 2>/dev/null)
[ -n "${warm:-}" ] || exit 0

clock=$(date -r "$warm" +%H:%M 2>/dev/null || date -d "@$warm" +%H:%M 2>/dev/null)
percent=$(awk -v c="$ctx" -v w="$window" 'BEGIN { printf "%d", c * 100 / w }')
dollars=$(awk -v d="$cost" 'BEGIN { printf "%.2f", d }')
[ "$unpriced" -gt 0 ] && dollars="$dollars ($unpriced unpriced)"

echo "$percent% context, $(human "$tokens") tokens, \$$dollars, $(energy "$kwh" "$grams"), cache until $clock"
