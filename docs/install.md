# Install

## Before you install

- These are my rules, and some are taste: every reply ends with feedback on your prompt, no long
  dashes, commit messages quote the prompts behind them, pull requests open as drafts. Read
  `CLAUDE.md`, or ask Claude to sum it up, and delete what you do not want.
- I use this on a Mac. The hooks need `jq`, which macOS has built in, and some need `gh`, GitHub's
  own command-line tool.

## Steps

1. Open Terminal and copy this repository to your computer:

   ```bash
   git clone https://github.com/lambdakilo/dotclaude.git ~/Projects/dotclaude
   ```

2. Pick one:

   a. Take only some pieces (recommended): open Claude Code and give it this prompt.

      ```text
      read ~/Projects/dotclaude/docs/what-you-get.md and the files it links. explain in plain words what each piece would change for me, then copy only the ones i say yes to into ~/.claude and add their settings to my settings.json without removing anything of mine
      ```

   b. Take everything. Each of your own files that it replaces is kept next to it with `.bak` at the
   end, such as `~/.claude/settings.json.bak`.

      ```bash
      ~/Projects/dotclaude/sync.sh --install
      ```

3. Quit Claude Code and open it again, so it loads the new setup.

To get my later changes, update your copy and then do step 2 again:

```bash
git -C ~/Projects/dotclaude pull
```

If you publish your own copy with `sync.sh --commit`, you can give the checkout a git identity of
its own, such as your GitHub noreply address, so the address your other repositories use stays out
of its public history:

```bash
git -C ~/Projects/dotclaude config user.name '<name>' && \
  git -C ~/Projects/dotclaude config user.email '<address>'
```

A `sync-deny.txt` beside `sync.sh`, which git ignores, lists words that must never be published, one
per line, such as the name of a project you work on: `sync.sh` refuses to publish a file that
contains one. The command below installs a hook that refuses a commit message with one too, in your
copy and in each folder that `sync-mirrors.txt` lists, replacing any commit-msg hook they have:

```bash
for dir in ~/Projects/dotclaude $(sed "s|^~|$HOME|" ~/Projects/dotclaude/sync-mirrors.txt 2>/dev/null); do
  hook="$(git -C "$dir" rev-parse --path-format=absolute --git-path hooks/commit-msg)" &&
    printf '#!/bin/sh\nexec "$HOME/Projects/dotclaude/sync.sh" --check-message "$1"\n' > "$hook" &&
    chmod +x "$hook"
done
```
