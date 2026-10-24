#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a git identity override: -c
# user.name= or -c user.email=, an assignment to a GIT_AUTHOR_ or GIT_COMMITTER_
# name or email variable, and git commit --author. A scratch or test repository
# commits under the configured identity too. Asks the user before git config
# sets or unsets user.name or user.email, since the user does ask for that.
# Quoted strings and heredoc bodies are not looked at.

set -u

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
case "$cmd" in
  *[Uu][Ss][Ee][Rr].[Nn][Aa][Mm][Ee]* | *[Uu][Ss][Ee][Rr].[Ee][Mm][Aa][Ii][Ll]* | \
    *GIT_AUTHOR_* | *GIT_COMMITTER_* | *--author*) ;;
  *) exit 0 ;;
esac

cmd="$(printf '%s\n' "$cmd" | awk '
  skip { t = $0; if (dash) sub(/^\t+/, "", t); if (t == end) skip = 0; next }
  {
    print
    if (match($0, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
      end = substr($0, RSTART, RLENGTH)
      sub(/^[^<]?<</, "", end)
      dash = substr(end, 1, 1) == "-"
      sub(/^-?[ \t]*["\047]?/, "", end)
      skip = 1
    }
  }' | awk '
  BEGIN { RS = "\001" }
  {
    s = ""; q = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (q != "\047" && c == "\\") {
        i++
        if (q == "") s = s (substr($0, i, 1) == "\n" ? " " : "_")
        continue
      }
      if (q == "" && (c == "\047" || c == "\"")) { q = c; s = s "_"; continue }
      if (q != "") { if (c == q) q = ""; continue }
      s = s c
    }
    gsub(/[0-9]*(>>?|<)&?[ \t]*[^ \t\n;&|()<>]*/, " ", s)
    gsub(/\n/, ";", s)
    print s
  }')"

sp='[[:space:]]'
word='[^[:space:];&|()]'
start="(^|[;&|({]|$sp(do|then|else))$sp*($word+=$word*$sp+)*($word*/)?git($sp+-[Cc]$sp+$word+)*"

if printf '%s\n' "$cmd" | grep -Eiq "(^|$sp)-c$sp*user\.(name|email)=" ||
  printf '%s\n' "$cmd" | grep -Eq "(^|[^A-Za-z0-9_])GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)=" ||
  printf '%s\n' "$cmd" | grep -Eiq "$start$sp+commit($sp[^;&|()]*)?$sp--author(=|$sp|\$)"; then
  cat >&2 <<'EOF'
Refused by ~/.claude/hooks/no-identity-override.sh: never override the git
author, in a scratch or test repository too. Commit under the identity that
git config user.name and git config user.email already give:

  a sandbox with its own HOME    cp ~/.gitconfig into that HOME first
  a second person a test needs   a Signed-off-by: <name> <address> trailer
  an existing commit's author    git commit -C <commit>, then
                                 git commit --amend -F <message file>

An identity change the user asked for goes through git config, which asks
them first.
EOF
  exit 2
fi

ask="$sp(--)?unset(-all)?$sp+([^;&|()]*$sp)?user\.(name|email)"
ask="$ask|$sp+user\.(name|email)$sp+[^[:space:];&|()-]"
printf '%s\n' "$cmd" | grep -Eio "$start$sp+config[^;&|()]*" | grep -Eiq "$ask" || exit 0

jq -n --arg r "git config is about to change the git user name or address. Approve only an \
identity change you asked for: a scratch or test repository commits under the configured \
identity too." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask",
    permissionDecisionReason: $r}}'
