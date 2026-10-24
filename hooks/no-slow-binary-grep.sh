#!/usr/bin/env bash

# Claude Code PreToolUse hook for Bash. Refuses grep, egrep, ggrep or ugrep
# with -a or --text and a quoted pattern that opens with a counted window, such
# as '.\{600\}NAME', '.{0,120}NAME' or '[^;]\{0,400\}NAME'. On a large binary
# such as the Claude Code build, ugrep and /usr/bin/grep alike run it for
# minutes, past the Bash tool's timeout. Heredoc bodies are not looked at.

set -u

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
case "$cmd" in *grep*) ;; *) exit 0 ;; esac
cmd="${cmd%%<<*}"
cmd="${cmd//$'\\\n'/ }"
cmd="$(printf '%s\n' "$cmd" | sed -E \
  -e "s/'(\\.|\\[[^]']*\\])\\\\?\\{[^']*'/@W@/g" \
  -e 's/"(\.|\[[^]"]*\])\\?\{[^"]*"/@W@/g' \
  -e "s/'[^']*'/_/g; s/\"[^\"]*\"/_/g")"
case "$cmd" in *@W@*) ;; *) exit 0 ;; esac

sp='[[:space:]]'
grep_word="(^|$sp)([^[:space:]]*/)?(e|g|u)?grep($sp|\$)"
text_flag="$sp(-[[:alnum:]]*a[[:alnum:]]*|--text|--binary-files=text)($sp|\$)"
hit=0
while IFS= read -r part; do
  case "$part" in *@W@*) ;; *) continue ;; esac
  printf '%s\n' "$part" | grep -Eq "$grep_word" || continue
  printf '%s\n' "$part" | grep -Eq "$text_flag" || continue
  hit=1
  break
done < <(printf '%s\n' "$cmd" | tr ';&|()`' '\n\n\n\n\n\n')

[ "$hit" -eq 1 ] || exit 0
cat >&2 <<'EOF'
Refused by ~/.claude/hooks/no-slow-binary-grep.sh: a grep -a pattern that
opens with a counted window, such as '.\{600\}NAME' or '[^;]\{0,400\}NAME',
runs for minutes on a large binary such as the Claude Code build, past the
Bash tool's timeout, with ugrep and /usr/bin/grep alike and LC_ALL=C or not.
For the text after a name, put the name first, as in 'NAME.\{0,200\}', with
a count of 255 or less for /usr/bin/grep. For the text before it, take the
byte offsets of the name as a fixed string, then print around each one:

  LC_ALL=C grep -a -b -o -F NAME "$CLAUDE_CODE_EXECPATH" | cut -d: -f1 | head
  dd if="$CLAUDE_CODE_EXECPATH" bs=1 skip=$((OFFSET - 600)) count=1200 \
    2>/dev/null | LC_ALL=C tr -c '[:print:]' .
EOF
exit 2
