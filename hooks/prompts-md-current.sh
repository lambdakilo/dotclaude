#!/usr/bin/env bash

# Claude Code PreToolUse hook on Bash. Blocks a git commit once in a checkout
# whose root holds the PROMPTS.md that prompts-md.sh writes, when the command
# neither runs prompts-md.sh nor names PROMPTS.md and the file has no change
# waiting, so the commit would leave it behind. The checkout comes from git -C
# or a cd in the command, with a variable the command itself assigns filled in,
# or else from the session's directory. An amend, the configuration checkout,
# whose sync.sh rebuilds the file, and the same command run again go through.

set -u

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
line="$(printf '%s\n' "$cmd" |
  grep -E '(^|[^A-Za-z0-9_./-])git( -[Cc] [^ ]+)* commit([^A-Za-z0-9_-]|$)' |
  grep -v -e '--amend' | head -n 1)"
[ -n "$line" ] || exit 0
case "$cmd" in *prompts-md.sh* | *PROMPTS.md*) exit 0 ;; esac
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
key="$(printf '%s' "$input" |
  jq -r '(.session_id // "") + (if (.agent_id // "") == "" then "" else "-" + .agent_id end)' 2>/dev/null)"
case "$key" in "" | *[!A-Za-z0-9_-]*) key=session ;; esac

expand() {
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#"~/"}" ;;
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$2/$1" ;;
  esac
}

# The value of the last NAME=value the command assigns, else of the variable
# in this environment.
value_of() {
  local value
  value="$(printf '%s\n' "$cmd" |
    grep -oE "(^|[;&|( ])$1=[^ ;&|)]+" | tail -n 1 |
    sed -E "s/^[;&|( ]?$1=//" | tr -d "\"'")"
  [ -n "$value" ] || value="$(printenv "$1" 2>/dev/null)"
  printf '%s\n' "$value"
}

resolve() {
  local word name value n=0
  word="$(printf '%s' "$1" | tr -d "\"'")"
  while :; do
    case "$word" in *'$'*) ;; *) break ;; esac
    [ "$n" -lt 5 ] || return 1
    name="$(printf '%s\n' "$word" | sed -nE 's/^[^$]*\$\{?([A-Za-z_][A-Za-z0-9_]*).*/\1/p')"
    [ -n "$name" ] || return 1
    value="$(value_of "$name")"
    [ -n "$value" ] || return 1
    case "$word" in
      *"\${$name}"*) word="${word/"\${$name}"/$value}" ;;
      *) word="${word/"\$$name"/$value}" ;;
    esac
    n=$((n + 1))
  done
  printf '%s\n' "$word"
}

seg="$(printf '%s\n' "$line" | grep -oE 'git( -[Cc] [^ ]+)* commit' | head -n 1)"
arg="$(printf '%s\n' "$seg" | sed -nE 's/.* -C ([^ ]+).*/\1/p')"
if [ -z "$arg" ]; then
  arg="$(printf '%s\n' "${cmd%%"$seg"*}" | grep -oE '(^|[;&|( ])cd [^ ;&|)]+' | tail -n 1 |
    sed -E 's/^[;&|( ]?cd //')"
fi
dir="$cwd"
if [ -n "$arg" ]; then
  arg="$(resolve "$arg")" || exit 0
  dir="$(expand "$arg" "$cwd")"
fi

top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$top" ] && [ "$top" != "$HOME/Projects/dotclaude" ] || exit 0
grep -q '^The prompts behind the commits of this repository' "$top/PROMPTS.md" 2>/dev/null || exit 0
[ -z "$(git -C "$top" status --porcelain -- PROMPTS.md 2>/dev/null)" ] || exit 0

state="${TMPDIR:-/tmp}/claude-prompts-md"
mkdir -p "$state" 2>/dev/null || exit 0
find "$state" -type f -mtime +7 -delete 2>/dev/null
mark="$state/$key-$(printf '%s' "$cmd" | cksum | cut -d ' ' -f 1)"
[ -f "$mark" ] && exit 0
: >"$mark" 2>/dev/null || exit 0

case "$top" in "$HOME"/*) shown="~/${top#"$HOME"/}" ;; *) shown="$top" ;; esac
cat >&2 <<EOF
Blocked once by ~/.claude/hooks/prompts-md-current.sh: $shown
keeps PROMPTS.md, and this command neither rebuilds nor stages it.
~/.claude/CLAUDE.md keeps the file current in every commit: run
~/.claude/hooks/prompts-md.sh --message <file> in that checkout and commit
PROMPTS.md with the change. When this commit should leave the file as it is,
run the command again unchanged.
EOF
exit 2
