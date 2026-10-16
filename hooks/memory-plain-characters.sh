#!/usr/bin/env bash

# Claude Code PostToolUse hook. Memory files take plain characters like every
# other text a session writes, but the built-in memory template joins an index
# entry's link and hook with an em dash, and sessions copy it. After each tool
# call this lists the em dashes in memory files changed in the last two
# minutes on stderr, which exit code 2 shows to the model.

set -u

projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
em_dash=$'\xe2\x80\x94'

hits="$(find "$projects"/*/memory -maxdepth 1 -name '*.md' -mmin -2 \
  -exec grep -Hn -F -e "$em_dash" {} + 2>/dev/null)"
[ -n "$hits" ] || exit 0

{
  echo "Em dashes in memory files, which take plain characters like any other text:"
  printf '%s\n' "$hits" | cut -d: -f1,2 | sed "s|^$HOME|~|; s/^/  /"
  echo "Rewrite each with a colon, comma or full stop. An index line is - [Title](file.md): hook."
} >&2
exit 2
