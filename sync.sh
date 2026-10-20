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
#   sync.sh --commit <message-file> [<path>...]
#                      sync, then commit the paths, all by default, with the
#                      message and push, then do the same in every mirror,
#                      the message gaining a line that names the commit here
#
# Reconciling: a file the pull changed is installed locally, a file changed
# locally is copied into the checkout, and a file changed on both sides stops
# the run. Literals listed one per line in sync-allow.txt are exempt from the
# scan.
#
# Key order: a mirrored JSON file changed locally is first put back into the
# key order the checkout has, when jq is installed, so a tool that writes the
# whole file back in its own order leaves a diff of the values alone.
#
# Literals listed one per line in sync-deny.txt, which git ignores, fail the
# scan wherever they appear, in any case: the names and labels of a private
# project. sync.sh --check-message <file> checks a commit message against the
# same list, for a commit-msg hook.
#
# Mirrors: directories listed one per line in sync-mirrors.txt, which git
# ignores, get a copy of every published file after a clean scan, for a second
# copy kept in another repository. A leading ~/ stands for the home directory.
# A file this checkout has deleted is removed from a mirror too.
#
# PROMPTS.md, when the checkout has one, is rebuilt by hooks/prompts-md.sh
# before the scan, with the commit message when there is one, and goes into
# every commit.

set -euo pipefail

source_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
checkout="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

message_file=""
commit_paths=(.)
if [ "${1:-}" = "--commit" ]; then
  if [ ! -f "${2:-}" ]; then
    echo "sync: --commit needs a message file" >&2
    exit 2
  fi
  message_file="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
  shift 2
  if [ "$#" -gt 0 ]; then
    commit_paths=("$@")
  fi
fi

deny_args=()
if [ -f "$checkout/sync-deny.txt" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "" | "#"*) ;;
      *) deny_args+=(-e "$line") ;;
    esac
  done < "$checkout/sync-deny.txt"
fi

if [ "${1:-}" = "--check-message" ]; then
  if [ "${#deny_args[@]}" -gt 0 ] && grep -v '^#' "$2" | grep -n -i -F "${deny_args[@]}" >&2; then
    echo "sync: the commit message names a term from sync-deny.txt" >&2
    exit 1
  fi
  exit 0
fi

mirrored=(
  CLAUDE.md
  settings.json
  hooks/calendar-free-busy-only.sh
  hooks/git-fetch-prune.sh
  hooks/git-prune-gone-branches.sh
  hooks/git-submodule-update-after-switch.sh
  hooks/check-not-piped.sh
  hooks/prompt-log.sh
  hooks/memory-plain-characters.sh
  hooks/stop-running-stack.sh
  hooks/stack-held-by-peer.sh
  hooks/claude-md-changed.sh
  hooks/no-github-posts.sh
  hooks/prompt-feedback-box.sh
  hooks/no-meta-prompts.sh
  hooks/prompts-md.sh
  hooks/cd-fall-through.sh
  mods/session-usage/.claude-plugin/plugin.json
  mods/session-usage/hooks/hooks.json
  mods/session-usage/hooks/register.ts
  mods/session-usage/hooks/register.test.ts
  mods/session-usage/usage.sh
  skills/pull-requests/SKILL.md
  workflows/dream.js
)

install_file() {
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
}

same_file() {
  [ "$(git hash-object "$1" 2>/dev/null)" = "$(git hash-object "$2" 2>/dev/null)" ]
}

same_as_commit() {
  [ "$(git rev-parse --verify --quiet "$1:$2")" = "$(git hash-object "$3")" ]
}

keep_key_order() {
  command -v jq >/dev/null 2>&1 || return 0
  same_file "$1" "$2" && return 0
  local ordered
  ordered="$(jq --slurpfile old "$1" '
    def order($o):
      if type == "object" and ($o | type) == "object" then
        . as $n
        | [($o | keys_unsorted[] | select(. as $k | $n | has($k))),
           ($n | keys_unsorted[] | select(. as $k | $o | has($k) | not))]
        | reduce .[] as $k ({}; .[$k] = ($n[$k] | order($o[$k])))
      else . end;
    order($old[0])' "$2" 2>/dev/null)" || return 0
  printf '%s\n' "$ordered" | cmp -s - "$2" || printf '%s\n' "$ordered" > "$2"
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
    case "$path" in *.json) keep_key_order "$repo_file" "$local_file" ;; esac
    same_file "$local_file" "$repo_file" || install_file "$local_file" "$repo_file"
  elif same_as_commit "$before" "$path" "$local_file"; then
    install_file "$repo_file" "$local_file"
  elif ! same_file "$local_file" "$repo_file"; then
    echo "sync: $path changed both locally and in the pulled commits, merge by hand" >&2
    failed=1
  fi
done

if [ -f "$checkout/PROMPTS.md" ]; then
  if [ -n "$message_file" ]; then
    "$checkout/hooks/prompts-md.sh" --message "$message_file"
    case " ${commit_paths[*]} " in *" . "* | *" PROMPTS.md "*) ;; *) commit_paths+=(PROMPTS.md) ;; esac
  else
    "$checkout/hooks/prompts-md.sh"
  fi
fi

allow_args=()
if [ -f "$checkout/sync-allow.txt" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ]; then
      allow_args+=(-e "$line")
    fi
  done < "$checkout/sync-allow.txt"
fi

mirror_dirs=()
if [ -f "$checkout/sync-mirrors.txt" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "") ;;
      "~/"*) mirror_dirs+=("$HOME/${line#"~/"}") ;;
      *) mirror_dirs+=("$line") ;;
    esac
  done < "$checkout/sync-mirrors.txt"
fi

files=()
scan_files=()
while IFS= read -r -d '' path; do
  [ -e "$path" ] || continue
  files+=("$path")
  case "$path" in LICENSE*|sync-allow.txt) continue ;; esac
  scan_files+=("$path")
done < <(git ls-files -z --cached --others --exclude-standard)
if [ "${#scan_files[@]}" -eq 0 ]; then
  exit "$failed"
fi

scan() {
  local label="$1"
  shift
  local hits
  hits="$(grep -n "$@" -- "${scan_files[@]}" 2>/dev/null || true)"
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
if [ "${#deny_args[@]}" -gt 0 ]; then
  scan "term from sync-deny.txt" -i -F "${deny_args[@]}"
fi
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

if [ "$failed" -eq 0 ] && [ "${#mirror_dirs[@]}" -gt 0 ]; then
  for dir in "${mirror_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      echo "sync: mirror directory $dir does not exist" >&2
      failed=1
      continue
    fi
    for path in "${files[@]}"; do
      install_file "$checkout/$path" "$dir/$path"
    done
    published=$'\n'"$(printf '%s\n' "${files[@]}")"$'\n'
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      case "$published" in *$'\n'"$path"$'\n'*) continue ;; esac
      rm -f "$dir/$path"
    done < <({
      git log --no-renames --diff-filter=D --name-only --format=
      git diff --cached --no-renames --diff-filter=D --name-only
      git ls-files --deleted
    } | sort -u)
    [ -n "$message_file" ] || echo "sync: published files copied into $dir, commit there too"
  done
fi

git status --short

if [ -n "$message_file" ] && [ "$failed" -ne 0 ]; then
  echo "sync: nothing committed, fix the above first" >&2
elif [ -n "$message_file" ]; then
  git add -A -- "${commit_paths[@]}"
  if git diff --cached --quiet -- "${commit_paths[@]}"; then
    echo "sync: nothing to commit here" >&2
  else
    git commit -q -F "$message_file" -- "${commit_paths[@]}"
  fi
  git push -q
  hash="$(git rev-parse --short HEAD)"
  echo "sync: $hash pushed"
  mirror_message="$(mktemp)"
  awk -v line="Mirrors $(basename "$checkout") $hash." '
    done == 0 && /^Prompts behind this commit/ { print line; print ""; done = 1 }
    { print }
    END { if (done == 0) { print ""; print line } }
  ' "$message_file" > "$mirror_message"
  for dir in ${mirror_dirs[@]+"${mirror_dirs[@]}"}; do
    git -C "$dir" pull --ff-only --quiet
    git -C "$dir" add -A -- "${commit_paths[@]}"
    git -C "$dir" diff --cached --quiet -- "${commit_paths[@]}" ||
      git -C "$dir" commit -q -F "$mirror_message" -- "${commit_paths[@]}"
    git -C "$dir" push -q
    echo "sync: $(git -C "$dir" rev-parse --short HEAD) pushed in $dir"
  done
  rm -f "$mirror_message"
fi
exit "$failed"
