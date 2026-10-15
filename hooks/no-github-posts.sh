#!/usr/bin/env bash

# Claude Code PreToolUse hook on Bash. Refuses the gh commands that post on
# GitHub under the user's name: a comment, a review, a review thread reply, a
# comment on closing or reopening, and resolving a review thread. Exit code 2
# blocks the call in every permission mode, bypassPermissions included, and
# hands stderr to the model. It reads the command text only, so a mutation
# kept in a file passed with --input gets through.

set -u

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

# Quoted text is dropped before looking for a gh command, so a grep or a jq
# filter that names one does not count. A double-quoted string with a $ in it
# stays, since it may hold a $(gh ...).
code="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"\$]*\"//g")"
gh='(^|[;&|({]|[[:space:]](do|then|else))[[:space:]]*([^[:space:];&|()]*/)?gh[[:space:]]+'

runs() {
  printf '%s\n' "$code" | grep -Eq -- "$gh$1"
}

block() {
  cat >&2 <<EOF
Blocked by ~/.claude/hooks/no-github-posts.sh: $1.
~/.claude/CLAUDE.md says never post a comment, a review thread reply, a review
or an issue comment on GitHub: every word posted goes out under the user's
name. Answer a review finding with the commit that fixes it, and tell the user
per thread what changed and in which commit, so they can answer and resolve
the threads themselves. Editing a PR body, assigning, and closing or reopening
without --comment stay allowed.
EOF
  exit 2
}

runs '(pr|issue)[[:space:]]+comment' && block "gh pr comment and gh issue comment post a comment"
runs 'pr[[:space:]]+review' && block "gh pr review posts a review"
runs '(pr|issue)[[:space:]]+(close|reopen)[^;&|]*[[:space:]](-c|--comment)([[:space:]=]|$)' &&
  block "--comment on a close or a reopen posts a comment"

runs 'api[[:space:]]' || exit 0
printf '%s\n' "$cmd" |
  grep -Eq 'add(Discussion)?Comment|addPullRequestReview|submitPullRequestReview|update(IssueComment|PullRequestReview)|resolveReviewThread' &&
  block "the GraphQL mutation posts, edits or resolves as the user"
call="$(printf '%s\n' "$cmd" | grep -oE 'gh[[:space:]]+api[[:space:]][^;&|]*' |
  grep -E '(issues|pulls)/[^[:space:]]*(comments|replies|reviews)')" || exit 0
printf '%s\n' "$call" | grep -Eq "(-X|--method)[[:space:]=]*[\"']?(POST|PATCH|PUT)" &&
  block "the call writes a comment, a reply or a review"
printf '%s\n' "$call" | grep -Eq '[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)' &&
  ! printf '%s\n' "$call" | grep -Eq "(-X|--method)[[:space:]=]*[\"']?GET" &&
  block "gh api sends fields as a POST without -X GET, so the call writes to a comments, replies or reviews path; add -X GET to read"
exit 0
