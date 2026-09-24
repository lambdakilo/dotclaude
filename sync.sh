#!/usr/bin/env bash

# Keeps the mirrored files in sync between the local Claude Code configuration
# directory and this checkout, in both directions, then scans everything that
# would be published for values that must stay private. Exits non-zero on a
# conflict or a scan hit, so nothing gets committed by reflex.
#
#   sync.sh            pull, reconcile, scan, show git status
#   sync.sh --install  copy every mirrored file from the checkout into the
#                      configuration directory (first run on a new machine);
#                      an existing file that differs is kept as <file>.bak
#
# Reconciling: a file the pull changed is installed locally, a file changed
# locally is copied into the checkout, and a file changed on both sides stops
# the run. Literals listed one per line in sync-allow.txt are exempt from the
# scan.

set -euo pipefail

source_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
checkout="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mirrored=(
  CLAUDE.md
  settings.json
  hooks/git-fetch-prune.sh
)

install_file() {
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
}

same_file() {
  [ "$(git hash-object "$1")" = "$(git hash-object "$2")" ]
}

same_as_commit() {
  [ "$(git rev-parse --verify --quiet "$1:$2")" = "$(git hash-object "$3")" ]
}

if [ "${1:-}" = "--install" ]; then
  for path in "${mirrored[@]}"; do
    target="$source_dir/$path"
    if [ -f "$target" ] && ! same_file "$checkout/$path" "$target"; then
      cp "$target" "$target.bak"
    fi
    install_file "$checkout/$path" "$target"
  done
  exit 0
fi

cd "$checkout"
before="$(git rev-parse HEAD)"
if ! git pull --ff-only --quiet 2>/dev/null; then
  echo "sync: pull failed, reconciling against the local HEAD only" >&2
fi

failed=0
for path in "${mirrored[@]}"; do
  local_file="$source_dir/$path"
  repo_file="$checkout/$path"
  if [ ! -f "$local_file" ]; then
    install_file "$repo_file" "$local_file"
    continue
  fi
  if git diff --quiet "$before" HEAD -- "$path"; then
    same_file "$local_file" "$repo_file" || install_file "$local_file" "$repo_file"
  elif same_as_commit "$before" "$path" "$local_file"; then
    install_file "$repo_file" "$local_file"
  elif ! same_file "$local_file" "$repo_file"; then
    echo "sync: $path changed both locally and in the pulled commits, merge by hand" >&2
    failed=1
  fi
done

allow_args=()
if [ -f "$checkout/sync-allow.txt" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ]; then
      allow_args+=(-e "$line")
    fi
  done < "$checkout/sync-allow.txt"
fi

files=()
while IFS= read -r -d '' path; do
  case "$path" in LICENSE*|sync-allow.txt) continue ;; esac
  files+=("$path")
done < <(git ls-files -z --cached --others --exclude-standard)
if [ "${#files[@]}" -eq 0 ]; then
  exit "$failed"
fi

scan() {
  local label="$1"
  shift
  local hits
  hits="$(grep -n "$@" -- "${files[@]}" 2>/dev/null || true)"
  if [ -n "$hits" ] && [ "${#allow_args[@]}" -gt 0 ]; then
    hits="$(printf '%s\n' "$hits" | grep -v -F "${allow_args[@]}" || true)"
  fi
  if [ -n "$hits" ]; then
    printf 'sync: %s in\n' "$label" >&2
    printf '%s\n' "$hits" | cut -d: -f1,2 | sed 's/^/  /' >&2
    failed=1
  fi
}

private_values=("$HOME")
login="$(id -un)"
if [ "$login" != root ]; then
  private_values+=("$login")
fi
for key in user.name user.email; do
  value="$(git config --global "$key" 2>/dev/null || true)"
  if [ -n "$value" ]; then
    private_values+=("$value")
  fi
  case "$value" in *@*) private_values+=("${value#*@}") ;; esac
done
for value in "${private_values[@]}"; do
  scan "local identity" -i -F -e "$value"
done

scan "home path" -E -e '/(Users|home)/[A-Za-z0-9._-]+'
scan "email address" -E -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "credential-like string" -E \
  -e '(gh[pousr]|github_pat)_[A-Za-z0-9_]{20,}' \
  -e 'sk-[A-Za-z0-9_-]{16,}' \
  -e 'xox[abprs]-[A-Za-z0-9-]+' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -e 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}' \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "credential-like assignment" -i -E \
  -e '(api[_-]?key|secret|token|passw(or)?d)[^A-Za-z0-9]{0,3}[:=][^A-Za-z0-9]{0,3}[A-Za-z0-9/+_.-]{16,}'

git status --short
exit "$failed"
