#!/usr/bin/env bash

# Claude Code SessionStart hook. Inside a repository that has remotes it
# fetches them with pruning, then deletes every local branch whose upstream
# branch is gone, as long as nothing on it would be lost: every commit is
# already on the base remote's default branch, or the branch tip is the head
# of a pull request that GitHub still holds. Any other gone branch stays and
# is named, so the decision is the user's. Whatever a SessionStart hook prints
# is added to the model's context, so it prints one line per outcome and
# nothing when there is nothing to tell.
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
    if git -C "$repo" show-ref --verify -q "refs/remotes/$base_remote/$name"; then
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

# Prints "delete<TAB>reason" or "keep<TAB>reason" for one gone branch.
judge() {
  local hash="$1" remote="$2" head_branch="$3"
  local head_slug prs state merged pr_hash number first=""
  if git -C "$repo" merge-base --is-ancestor "$hash" "$default_ref" 2>/dev/null; then
    printf 'delete\ton %s/%s\n' "$base_remote" "$default_branch"
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
    if [ "$pr_hash" = "$hash" ] || git -C "$repo" merge-base --is-ancestor "$hash" "$pr_hash" 2>/dev/null; then
      if [ "$merged" = true ]; then
        printf 'delete\thead of merged pull request #%s\n' "$number"
      else
        printf 'delete\thead of closed pull request #%s\n' "$number"
      fi
      return
    fi
    [ -n "$first" ] || first="$number"
  done <<PRS
$prs
PRS
  printf 'keep\tahead of pull request #%s\n' "$first"
}

log="$common_dir/claude-code-deleted-branches.log"
deleted="" n_deleted=0
kept="" n_kept=0
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
        n_kept=$((n_kept + 1))
        continue
      fi
    fi
    deleted="$deleted${deleted:+, }$name ($reason)"
    n_deleted=$((n_deleted + 1))
  else
    kept="$kept${kept:+, }$name ($reason)"
    n_kept=$((n_kept + 1))
  fi
done < <(git -C "$repo" for-each-ref \
  --format='%(refname:short)%1f%(objectname)%1f%(upstream:remotename)%1f%(upstream:remoteref)%1f%(upstream:track)' \
  refs/heads)

plural() { [ "$1" -eq 1 ] && printf 'branch' || printf 'branches'; }
if [ "$n_deleted" -gt 0 ]; then
  if [ "$dry_run" -eq 1 ]; then
    printf 'Would delete %d local %s whose remote branch is gone and whose commits GitHub still holds: %s.\n' \
      "$n_deleted" "$(plural "$n_deleted")" "$deleted"
  else
    printf 'Deleted %d local %s whose remote branch is gone and whose commits GitHub still holds: %s. Restore one with git branch <name> <hash>, both listed in %s.\n' \
      "$n_deleted" "$(plural "$n_deleted")" "$deleted" "$log"
  fi
fi
if [ "$n_kept" -gt 0 ]; then
  printf 'Kept %d local %s whose remote branch is gone but that may hold unpushed work: %s. Delete only what the user names.\n' \
    "$n_kept" "$(plural "$n_kept")" "$kept"
fi

exit 0
