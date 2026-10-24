#!/usr/bin/env bash

# Rewraps prose that an edit left unwrapped in the files this checkout keeps at
# 100 columns: CLAUDE.md, README.md and the pull-requests skill. A paragraph
# that differs from the checkout's last commit, or has a line over 100
# columns, is filled greedily from the line before its first changed line, a
# list item's later lines indented under its text. Every other paragraph keeps
# its breaks, and front matter, code blocks, tables, headings, quotes, HTML and
# the README's evals block stay as they are. Run it on its own rather than
# chained with sync.sh, so the CLAUDE.md watcher hook counts the change as the
# session's own edit.
#
#   reflow.sh           both copies of CLAUDE.md and of the skill, and README.md
#   reflow.sh <file>... those files, in this checkout or in the configuration
#                       directory, each compared with its path's last commit

set -euo pipefail

source_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
checkout="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -eq 0 ]; then
  set -- "$checkout/README.md"
  for path in CLAUDE.md skills/pull-requests/SKILL.md; do
    set -- "$@" "$source_dir/$path" "$checkout/$path"
  done
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for file in "$@"; do
  file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
  case "$file" in
    "$checkout"/*) path="${file#"$checkout"/}" ;;
    "$source_dir"/*) path="${file#"$source_dir"/}" ;;
    *)
      echo "reflow: $file is in neither $checkout nor $source_dir" >&2
      exit 2
      ;;
  esac
  changed="$({ git -C "$checkout" show "HEAD:$path" 2>/dev/null || true; } | diff - "$file" | awk '
    /^[0-9]/ {
      split($0, side, /[acd]/); n = split(side[2], r, ",")
      if ($0 ~ /d/) printf "%d,%d,", r[1], r[1] + 1
      else for (i = r[1]; i <= r[n]; i++) printf "%d,", i
    }')" || true
  LC_ALL=C awk -v width=100 -v changed="$changed" '
    function clen(s) { gsub(/[\200-\277]/, "", s); return length(s) }
    function flush(   i, k, n, w, from, words, line, prev, count) {
      if (np == 0) return
      from = 0
      for (i = 1; i <= np && !from; i++)
        if ((start + i - 1) in touched || clen(pl[i]) > width) from = i > 1 ? i - 1 : 1
      for (i = 1; i <= (from ? from - 1 : np); i++) print pl[i]
      if (from) {
        words = ""
        for (i = from; i <= np; i++) words = words " " pl[i]
        n = split(words, w, " ")
        line = (from == 1 ? ind : cont) w[1]; count = 1
        for (k = 2; k <= n; k++)
          if (clen(line) + 1 + clen(w[k]) <= width) { prev = line; line = line " " w[k]; count++ }
          else if (w[k] ~ /^([-*+>]|#+|1[.)])$/ && count > 2) {
            print prev; line = cont substr(line, length(prev) + 2) " " w[k]; count = 2
          } else { print line; line = cont w[k]; count = 1 }
        print line
      }
      np = 0
    }
    BEGIN { n = split(changed, c, ","); for (i = 1; i <= n; i++) if (c[i] != "") touched[c[i]] = 1 }
    FNR == 1 { front = ($0 == "---") }
    front { if (FNR > 1 && $0 == "---") front = 0; print; next }
    /^[ \t]*```/ { flush(); code = !code; print; next }
    code { print; next }
    /^<!-- evals:start -->/ { flush(); evals = 1 }
    evals { if (/^<!-- evals:end -->/) evals = 0; print; next }
    /^[ \t]*$/ || /^[ \t]*([|#><]|!\[)/ { flush(); print; next }
    match($0, /^ *([-*+]|[0-9]+[.)]) +/) {
      flush(); ind = $0; sub(/[^ ].*/, "", ind); cont = sprintf("%" RLENGTH "s", "")
      start = FNR; np = 1; pl[1] = $0; next
    }
    np == 0 { ind = $0; sub(/[^ ].*/, "", ind); cont = ind; start = FNR; np = 1; pl[1] = $0; next }
    { pl[++np] = $0 }
    END { flush() }
  ' "$file" > "$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" > "$file"
    echo "reflow: rewrapped $file"
  fi
done
