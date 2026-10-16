#!/usr/bin/env bash

# Claude Code SessionStart hook. Inside a repository that has remotes it
# fetches them with pruning, then deletes every local branch whose upstream
# branch is gone, as long as nothing on it would be lost: every commit, or a
# patch-equivalent one, is already on the base remote's default branch or in a
# pull request that GitHub still holds. Any other gone branch stays and is
# named, so the decision is the user's. The notice goes to the user as a
# system message and to the model as context, and only when there is news: a
# deletion, or a kept set other than the one last named, which is recorded in
# claude-code-kept-branches in the git directory.
#
#   --dry-run   report what would be deleted and kept, delete nothing
#
# Deleted names and hashes go to claude-code-deleted-branches.log in the git
# directory, and `git branch <name> <hash>` brings one back.

set -u

dry_run=0
[ "${1:-}" = --dry-run ] && dry_run=1
repo="${CLAUDE_PROJECT_DIR:-$PWD}"

# Subagents start sessions too; the main session has already done this work.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"
case "$input" in *'"agent_type"'*) exit 0 ;; esac

common_dir="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || exit 0
case "$common_dir" in
  /*) ;;
  *) common_dir="$repo/$common_dir" ;;
esac
[ -n "$(git -C "$repo" remote 2>/dev/null)" ] || exit 0

fetch_hook="$(dirname "$0")/git-fetch-prune.sh"
[ -x "$fetch_hook" ] && "$fetch_hook"

base_remote=origin
git -C "$repo" remote get-url upstream >/dev/null 2>&1 && base_remote=upstream

default_ref="$(git -C "$repo" symbolic-ref -q "refs/remotes/$base_remote/HEAD" 2>/dev/null)"
if [ -z "$default_ref" ]; then
  for name in main master dev develop trunk; do
    if git --no-pager -C "$repo" show-ref --verify -q "refs/remotes/$base_remote/$name"; then
      default_ref="refs/remotes/$base_remote/$name"
      break
    fi
  done
fi
[ -n "$default_ref" ] || exit 0
default_branch="${default_ref#refs/remotes/"$base_remote"/}"

github_slug() {
  local url
  url="$(git -C "$repo" remote get-url "$1" 2>/dev/null)" || return 1
  case "$url" in *github.com[:/]*) ;; *) return 1 ;; esac
  url="${url##*github.com[:/]}"
  url="${url%/}"
  url="${url%.git}"
  case "$url" in */*/*|*/|/*) return 1 ;; */*) printf '%s\n' "$url" ;; *) return 1 ;; esac
}

base_slug="$(github_slug "$base_remote")" || base_slug=""
checked_out="$(git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p')"
ssh_command="${GIT_SSH_COMMAND:-$(git -C "$repo" config core.sshCommand 2>/dev/null || echo ssh)}"

plural() { [ "$1" -eq 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

# GitHub keeps refs/pull/<n>/head after the branch is deleted, so a head pushed
# from another clone, or deleted before the last fetch, can still be compared.
fetch_pr_head() {
  git -C "$repo" cat-file -e "$2^{commit}" 2>/dev/null && return 0
  GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS=true \
  GIT_SSH_COMMAND="$ssh_command -o BatchMode=yes" \
    git -C "$repo" fetch --quiet --no-tags --no-write-fetch-head \
    "$base_remote" "refs/pull/$1/head" </dev/null >/dev/null 2>&1
  git -C "$repo" cat-file -e "$2^{commit}" 2>/dev/null
}

# Prints how many commits on $2 have no patch-equivalent commit on $1. Merges
# count as unmatched, since git cherry skips them and their resolutions.
unmatched() {
  local marks merges
  marks="$(git -C "$repo" cherry "$1" "$2" 2>/dev/null)" || return 1
  merges="$(git -C "$repo" rev-list --count --merges "$1..$2" 2>/dev/null)" || return 1
  printf '%s\n' "$(( $(printf '%s\n' "$marks" | grep -c '^+') + merges ))"
}

# Prints "delete<TAB>reason" or "keep<TAB>reason" for one gone branch.
judge() {
  local hash="$1" remote="$2" head_branch="$3"
  local head_slug prs state merged pr_hash number kind left note=""
  if git -C "$repo" merge-base --is-ancestor "$hash" "$default_ref" 2>/dev/null; then
    printf 'delete\ton %s/%s\n' "$base_remote" "$default_branch"
    return
  fi
  if [ "$(unmatched "$default_ref" "$hash")" = 0 ]; then
    printf 'delete\tpatches on %s/%s\n' "$base_remote" "$default_branch"
    return
  fi
  if [ -z "$base_slug" ] || ! head_slug="$(github_slug "$remote")"; then
    printf 'keep\tnot on GitHub\n'
    return
  fi
  prs="$(GH_PROMPT_DISABLED=1 gh api -X GET "repos/$base_slug/pulls" \
    -f state=all -f per_page=20 -f "head=${head_slug%%/*}:$head_branch" \
    --jq '.[] | "\(.state)\t\(.merged_at != null)\t\(.head.sha)\t\(.number)"' 2>/dev/null)" || {
    printf 'keep\tpull request lookup failed\n'
    return
  }
  if [ -z "$prs" ]; then
    printf 'keep\tno pull request found\n'
    return
  fi
  while IFS="$(printf '\t')" read -r state merged pr_hash number; do
    if [ "$state" = open ]; then
      printf 'keep\topen pull request #%s\n' "$number"
      return
    fi
    kind=closed
    [ "$merged" = true ] && kind=merged
    if ! fetch_pr_head "$number" "$pr_hash"; then
      [ -n "$note" ] || note="head of $kind pull request #$number not fetched"
      continue
    fi
    if [ "$pr_hash" = "$hash" ] || git -C "$repo" merge-base --is-ancestor "$hash" "$pr_hash" 2>/dev/null; then
      printf 'delete\thead of %s pull request #%s\n' "$kind" "$number"
      return
    fi
    left="$(unmatched "$pr_hash" "$hash")" || left=""
    if [ "$left" = 0 ]; then
      printf 'delete\tpatches in %s pull request #%s\n' "$kind" "$number"
      return
    fi
    [ -n "$note" ] || note="ahead of $kind pull request #$number${left:+ by $left $(plural "$left" commit commits)}"
  done <<PRS
$prs
PRS
  printf 'keep\t%s\n' "$note"
}

log="$common_dir/claude-code-deleted-branches.log"
state_file="$common_dir/claude-code-kept-branches"
deleted="" n_deleted=0
kept="" n_kept=0 kept_set=""
separator="$(printf '\037')"
tab="$(printf '\t')"
while IFS="$separator" read -r name hash remote remoteref track; do
  [ "$track" = "[gone]" ] || continue
  [ "$name" != "$default_branch" ] || continue
  printf '%s\n' "$checked_out" | grep -qxF -- "$name" && continue
  verdict="$(judge "$hash" "$remote" "${remoteref#refs/heads/}")"
  reason="${verdict#*"$tab"}"
  if [ "${verdict%%"$tab"*}" = delete ]; then
    if [ "$dry_run" -eq 0 ]; then
      if git -C "$repo" branch -D "$name" >/dev/null 2>&1; then
        printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$hash" "$reason" >> "$log"
      else
        reason="could not delete"
        kept="$kept${kept:+, }$name ($reason)"
        kept_set="$kept_set$name $hash "
        n_kept=$((n_kept + 1))
        continue
      fi
    fi
    deleted="$deleted${deleted:+, }$name ($reason)"
    n_deleted=$((n_deleted + 1))
  else
    kept="$kept${kept:+, }$name ($reason)"
    kept_set="$kept_set$name $hash "
    n_kept=$((n_kept + 1))
  fi
done < <(git -C "$repo" for-each-ref \
  --format='%(refname:short)%1f%(objectname)%1f%(upstream:remotename)%1f%(upstream:remoteref)%1f%(upstream:track)' \
  refs/heads)

notice="" context=""
if [ "$n_deleted" -gt 0 ]; then
  if [ "$dry_run" -eq 1 ]; then
    notice="$(printf 'Would delete %d local %s whose remote branch is gone and whose commits GitHub still holds: %s.' \
      "$n_deleted" "$(plural "$n_deleted" branch branches)" "$deleted")"
  else
    notice="$(printf 'Deleted %d local %s whose remote branch is gone and whose commits GitHub still holds: %s. Restore one with git branch <name> <hash>, both listed in %s.' \
      "$n_deleted" "$(plural "$n_deleted" branch branches)" "$deleted" "$log")"
  fi
fi
if [ "$n_kept" -gt 0 ] && { [ "$dry_run" -eq 1 ] || [ "$kept_set" != "$(cat "$state_file" 2>/dev/null)" ]; }; then
  notice="$notice${notice:+ }$(printf 'Kept %d local %s whose remote branch is gone but that may hold unpushed work: %s.' \
    "$n_kept" "$(plural "$n_kept" branch branches)" "$kept")"
  context=" The user has seen this list and decides which of them to delete."
fi
if [ "$dry_run" -eq 0 ]; then
  if [ "$n_kept" -gt 0 ]; then
    { printf '%s\n' "$kept_set" > "$state_file"; } 2>/dev/null
  else
    rm -f "$state_file"
  fi
fi

[ -n "$notice" ] || exit 0
if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' "$notice"
elif command -v jq >/dev/null 2>&1; then
  jq -n --arg notice "$notice" --arg context "$notice$context" \
    '{systemMessage: $notice, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}}'
else
  printf '%s\n' "$notice$context"
fi
exit 0
