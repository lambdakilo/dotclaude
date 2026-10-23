#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses git checkout, also after
# git -C <dir>. It both changes branches and overwrites files and picks by what
# its arguments name, so a typo or a stray path can overwrite work; git switch
# and git restore cover every use, and stderr names them. Quoted strings and
# heredoc bodies are not looked at, and gh pr checkout goes through.

set -u

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0
cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="$(printf '%s\n' "$cmd" | sed -E "s/'[^']*'/_/g; s/\"[^\"]*\"/_/g")"

sp='[[:space:]]'
word='[^[:space:];&|()]'
printf '%s\n' "$cmd" |
  grep -Eq "(^|[;&|({]|$sp(do|then|else))$sp*($word*/)?git($sp+-C$sp+$word+)?$sp+checkout($sp|\$)" ||
  exit 0

cat >&2 <<'EOF'
Refused by ~/.claude/hooks/no-git-checkout.sh: git checkout both changes
branches and overwrites files, and picks by what its arguments name, so a typo
or a stray path can overwrite work. Use the command for the one job:

  git switch <branch>                                        change branch
  git switch -c <new>                                        create a branch
  git switch --detach <commit>                               detach at a commit
  git restore <path>                                         file from the index
  git restore --source <commit> --staged --worktree <path>   file from a commit
  git restore --ours <path>, git restore --theirs <path>     side of a conflict
EOF
exit 2
