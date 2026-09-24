#!/usr/bin/env bash

# Claude Code UserPromptSubmit hook. Inside a repository that has remotes it
# fetches all of them with pruning, at most once per interval per repository,
# so remote-tracking refs stay fresh without a prompt ever waiting on the
# network or on a credential prompt. It prints nothing, because whatever a
# UserPromptSubmit hook prints is added to the model's context.

set -u

interval_minutes="${CLAUDE_GIT_FETCH_INTERVAL_MINUTES:-15}"
repo="${CLAUDE_PROJECT_DIR:-$PWD}"

common_dir="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || exit 0
case "$common_dir" in
  /*) ;;
  *) common_dir="$repo/$common_dir" ;;
esac
[ -n "$(git -C "$repo" remote 2>/dev/null)" ] || exit 0

stamp="$common_dir/claude-code-fetch.stamp"
[ -z "$(find "$stamp" -mmin "-$interval_minutes" 2>/dev/null)" ] || exit 0
touch "$stamp" 2>/dev/null || exit 0

ssh_command="${GIT_SSH_COMMAND:-$(git -C "$repo" config core.sshCommand 2>/dev/null || echo ssh)}"
GIT_TERMINAL_PROMPT=0 \
GIT_ASKPASS=true \
GIT_SSH_COMMAND="$ssh_command -o BatchMode=yes" \
  git -C "$repo" fetch --all --prune --quiet >/dev/null 2>&1

exit 0
