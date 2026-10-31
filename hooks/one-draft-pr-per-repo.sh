#!/usr/bin/env bash

# Claude Code PreToolUse hook on Bash. Refuses gh pr create once while the user
# has a draft PR open in the target repository, since ~/.claude/CLAUDE.md opens
# a new one only for an issue or feature the user asked to start and sends
# every other change to a draft already open. The target is the --repo or -R
# the command names, else the repository gh finds from the session's working
# directory. It refuses once per session for the same set of open drafts, and
# any gh failure lets the command through.

set -u

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

# Quoted text is dropped before looking for the gh command, as in
# no-github-posts.sh, so a grep or an echo that names one does not count.
code="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"\$]*\"//g")"
gh='(^|[;&|({]|[[:space:]](do|then|else))[[:space:]]*([^[:space:];&|()]*/)?gh[[:space:]]+'
printf '%s\n' "$code" | grep -Eq -- "${gh}pr[[:space:]]+create" || exit 0

repo="$(printf '%s\n' "$cmd" | grep -oE -- '(--repo[= ]|-R )[^[:space:];&|]+' | head -n 1 |
  sed -E "s/^(--repo[= ]|-R )//; s/[\"']//g")"
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
args=(pr list --author @me --state open --draft --json number,headRefName,url
  --jq '.[] | "  #\(.number) (\(.headRefName)) \(.url)"')
[ -z "$repo" ] || args+=(--repo "$repo")
drafts="$(cd "${dir:-.}" 2>/dev/null && gh "${args[@]}" 2>/dev/null)" || exit 0
[ -n "$drafts" ] || exit 0

key="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
case "$key" in "" | *[!A-Za-z0-9_-]*) key=session ;; esac
state="${TMPDIR:-/tmp}/claude-one-draft-pr"
mkdir -p "$state" 2>/dev/null || exit 0
find "$state" -type f -mtime +7 -delete 2>/dev/null
mark="$state/$key-$(printf '%s' "$drafts" | cksum | cut -d ' ' -f 1)"
[ -f "$mark" ] && exit 0
: >"$mark" 2>/dev/null || exit 0

cat >&2 <<EOF
Blocked once by ~/.claude/hooks/one-draft-pr-per-repo.sh, so no part of the
command ran: the user has a draft PR open in this repository:
$drafts
~/.claude/CLAUDE.md opens a draft PR only for an issue or feature the user
asked to start: commit any other change to the branch of the PR in play, or of
that draft, and refresh its body, and when another live session holds it, send
the change to that session with SendMessage, to the name ListAgents prints. A
body file this command writes, as with a cat heredoc, was not written. Run the
command again unchanged only when the user asked in this session to start an
issue or feature, or to open a new PR.
EOF
exit 2
