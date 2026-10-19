#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a command in which a part after
# a ; or a line break still runs when a cd before it fails, inside a subshell
# too. That part then runs in the start directory, which in a shared checkout
# holds another session's branch. A cd guarded with || exit or || return, a
# plain cd after set -e, and a cd into a directory that exists already go
# through. Plain assignments in the command are resolved in the cd target, and
# heredoc bodies are not looked at. The parsing is a heuristic.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
case "$cmd" in
  *cd[[:space:]]*) ;;
  *) exit 0 ;;
esac
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"

targets="$(printf '%s' "$cmd" | awk '
  BEGIN { RS = "\001" }
  {
    s = ""; q = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (q != "\047" && c == "\\") { s = s "__"; i++; continue }
      if (q == "" && (c == "\047" || c == "\"")) q = c
      else if (q != "" && c == q) q = ""
      else if (q != "" && index(";&|()\n", c)) c = "_"
      s = s c
    }
    gsub(/[<>]&|&>/, "__", s)
    gsub(/(&&|\|\||\|)[ \t]*\n/, "& ", s)
    gsub(/\n/, ";", s)
    t = s
    while (match(t, /(^|[;&|(])[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=("[^"`]*"|\047[^\047]*\047|[^ \t;&|()"`\047]+)/)) {
      a = substr(t, RSTART, RLENGTH)
      t = substr(t, RSTART + RLENGTH)
      sub(/^[;&|(]?[ \t]*(export[ \t]+)?/, "", a)
      k = index(a, "=")
      v = substr(a, k + 1)
      gsub(/["\047]/, "", v)
      vars[substr(a, 1, k - 1)] = v
    }
    before = ""
    while (match(s, /(^|[;&|(])[ \t]*((then|do|else|\{)[ \t]+)?cd[ \t]+[^;&|)]*/)) {
      target = substr(s, RSTART, RLENGTH)
      before = before substr(s, 1, RSTART - 1)
      s = substr(s, RSTART + RLENGTH)
      r = s
      guarded = 0
      while (match(r, /^(&&|\|\||\|)[^;&|)]*/)) {
        if (substr(r, 1, RLENGTH) ~ /^\|\|[ \t]*(exit|return)/) { guarded = 1; break }
        r = substr(r, RLENGTH + 1)
      }
      if (r == s && before ~ /set[ \t]+-[a-z]*e|errexit/) guarded = 1
      if (guarded || r !~ /^;[ \t;]*[^ \t;)]/) continue
      if (r ~ /^;[ \t;]*(done|fi|esac|then|else|elif|do|\})([ \t;)]|$)/) continue
      sub(/^[;&|(]?[ \t]*((then|do|else|\{)[ \t]+)?cd[ \t]+/, "", target)
      sub(/^(-[LPe@]+[ \t]+)+/, "", target)
      qc = substr(target, 1, 1)
      if (qc == "\"" || qc == "\047") {
        k = index(substr(target, 2), qc)
        if (k) target = substr(target, 1, k + 1)
      } else sub(/[ \t].*/, "", target)
      for (name in vars) {
        if (index(vars[name], "$" name)) continue
        gsub("\\$\\{" name "\\}", vars[name], target)
        while (match(target, "\\$" name "([^A-Za-z0-9_]|$)"))
          target = substr(target, 1, RSTART - 1) vars[name] substr(target, RSTART + 1 + length(name))
      }
      print (target == "" ? "." : target)
    }
  }')"
[ -n "$targets" ] || exit 0

risky=""
while IFS= read -r t; do
  d="${t//\$\{HOME\}/$HOME}"
  d="${d//\$HOME/$HOME}"
  case "$d" in
    *'$'* | *'`'* | *'*'* | *'?'* | -) risky="$t"; break ;;
  esac
  d="${d//\"/}"
  d="${d//\'/}"
  case "$d" in
    "~") d="$HOME" ;;
    "~/"*) d="$HOME/${d#\~/}" ;;
    /*) ;;
    *) d="${cwd:-$PWD}/$d" ;;
  esac
  [ -d "$d" ] || { risky="$t"; break; }
done <<EOF
$targets
EOF
[ -n "$risky" ] || exit 0

cat >&2 <<EOF
Refused: a part of this command after a ; or a line break still runs when
cd $risky fails, which this hook cannot rule out, and it then runs in the
start directory, inside a subshell too. In a shared checkout that directory
holds another session's branch. Make every part depend on the cd:

  (cd <dir> || exit 1; first; second)

or join the parts with &&, or use the tool's own directory flag, such as
git -C. A directory that another call creates is created in an earlier
message, never in one sent alongside this call.
EOF
exit 2
