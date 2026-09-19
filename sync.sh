#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Copies the mirrored files from the local Claude Code configuration directory
# into this checkout, then scans everything that would be published for values
# that must stay private: the local user name and home path, the git identity,
# email addresses, and strings that look like credentials. Exits non-zero when
# the scan finds any, so nothing gets committed by reflex.

set -euo pipefail

source_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
checkout="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mirrored=(
  CLAUDE.md
  settings.json
  hooks/git-fetch-prune.sh
)

for path in "${mirrored[@]}"; do
  mkdir -p "$checkout/$(dirname "$path")"
  cp "$source_dir/$path" "$checkout/$path"
done

if command -v jq >/dev/null 2>&1; then
  jq empty "$checkout/settings.json"
fi

files=()
while IFS= read -r -d '' path; do
  case "$path" in LICENSE*) continue ;; esac
  files+=("$path")
done < <(cd "$checkout" && git ls-files -z --cached --others --exclude-standard)
[ "${#files[@]}" -gt 0 ] || exit 0

failed=0
scan() {
  local label="$1"
  shift
  local hits
  if hits="$(cd "$checkout" && grep -n "$@" -- "${files[@]}" 2>/dev/null | cut -d: -f1,2)"; then
    printf 'sync: %s in\n' "$label" >&2
    printf '%s\n' "$hits" | sed 's/^/  /' >&2
    failed=1
  fi
}

private_values=("$HOME" "$(id -un)")
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

(cd "$checkout" && git status --short)
exit "$failed"
