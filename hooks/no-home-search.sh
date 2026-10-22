#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses a search that walks the whole
# disk or the home folder: find, bfs, fd, rg, tree, du, grep -r or ls -R
# rooted at /, /Users, /Volumes, a home folder or ~/*, or at . after a cd
# there, and mdfind without -onlyin. macOS asks the user about each protected
# folder such a walk reaches, and the command waits for the answer. Quoted
# strings other than "$HOME" and heredoc bodies are not looked at.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="$(printf '%s\n' "$cmd" | sed -E \
  -e 's/"\$\{?HOME\}?(\/\*?)?"/$HOME\1/g' -e 's/\$\{HOME\}/$HOME/g' \
  -e "s/'[^']*'//g" -e 's/"[^"]*"//g')"

at_root=0
case "$cwd" in "$HOME" | /) at_root=1 ;; esac

is_root() {
  local p="${1%/\*}"
  p="${p%/}"
  case "$p" in
    '' | '~' | '$HOME' | /Users | /Volumes | /System/Volumes/Data) return 0 ;;
    /Users/*/*) return 1 ;;
    /Users/*) return 0 ;;
    . | '*') [ "$at_root" -eq 1 ] ;;
    *) return 1 ;;
  esac
}

has_flag() {
  local short="$1" long="$2" a
  shift 2
  for a in "$@"; do
    case "$a" in
      --*) [ "$a" = "$long" ] && return 0 ;;
      -*) case "${a#-}" in *[$short]*) return 0 ;; esac ;;
    esac
  done
  return 1
}

hit=""
set -f
while IFS= read -r line; do
  set -- $line
  while [ "$#" -gt 0 ]; do
    case "$1" in
      *=* | sudo | command | env | exec | time | nice | nohup | then | do | else | '{' | '!') shift ;;
      *) break ;;
    esac
  done
  [ "$#" -gt 0 ] || continue
  name="${1##*/}"
  shift
  case "$name" in
    cd)
      at_root=0
      if [ "$#" -eq 0 ] || is_root "$1"; then at_root=1; fi
      continue ;;
    find | bfs | fd | fdfind | rg | tree | du) ;;
    grep | egrep | fgrep | ggrep) has_flag rR --recursive "$@" || continue ;;
    ls | gls) has_flag R --recursive "$@" || continue ;;
    mdfind)
      case " $* " in *" -onlyin "*) continue ;; esac
      hit="mdfind without -onlyin"
      break ;;
    *) continue ;;
  esac
  for a in "$@"; do
    if is_root "$a"; then hit="$name $a"; break 2; fi
  done
done < <(printf '%s\n' "$cmd" | tr ';&|()`' '\n\n\n\n\n\n')

[ -n "$hit" ] || exit 0
cat >&2 <<EOF
Refused by ~/.claude/hooks/no-home-search.sh: $hit reaches the whole disk or
the home folder. macOS asks the user about each protected folder such a search
touches, and the command waits for the answer. Search the project, ~/Projects,
~/.claude, ~/Downloads or the folder the user named, and give mdfind -onlyin.
For a file the user mentioned, stat the path it is likely at, then ask.
ls -a ~ lists the home folder itself.
EOF
exit 2
