# dotclaude

Claude Code is the AI that writes code for you, in a terminal or in the Claude desktop app. It
reads its setup from a hidden folder on your computer, `~/.claude`. This repository is a public
copy of my setup, so you can borrow from it.

Claude Code is good at writing code, but left alone it makes some of the same mistakes again and
again. Most of this setup stops those mistakes before they happen.

## Why this is public

I think this is the next step for free software and open source. Many projects now write their
code with AI, but they give back only the source code, never how they used the AI. If a project
calls itself open, it should put its money where its mouth is and publish that too. This
repository is my part: the rules and hooks I work with are here, and every commit quotes the
prompts behind it, collected in [`PROMPTS.md`](PROMPTS.md).

## Words you will see

- **Repository** (repo): a project folder that git keeps the history of, usually also on GitHub.
- **Commit**: a saved snapshot of changes, with a message saying what changed.
- **Pull request** (PR): asking for your changes to be added to the main version, so others can
  review them first.
- **Hook**: a small script Claude Code runs by itself at a set moment, such as before every
  command. A hook can stop a command before it runs. You never start one yourself.
- **Skill**: written instructions Claude Code reads only when a task needs them.
- **Terminal**: the app where you type commands. On a Mac it is called Terminal.

## What you get

### Stops mistakes

- [`check-not-piped.sh`](hooks/check-not-piped.sh): stops Claude from reporting failed tests as
  passed, which happens when the test output goes through another command.
- [`no-github-posts.sh`](hooks/no-github-posts.sh): stops Claude from posting comments or reviews
  on GitHub, where they would appear under your name.
- [`no-home-search.sh`](hooks/no-home-search.sh): stops searches of your whole disk, which make
  the Mac ask you for permission folder after folder.
- [`cd-fall-through.sh`](hooks/cd-fall-through.sh): stops a command from carrying on in the wrong
  folder when moving to the right one failed.
- [`calendar-free-busy-only.sh`](hooks/calendar-free-busy-only.sh): stops Claude from reading
  other people's calendar events. It can still see when they are free.
- [`stop-running-stack.sh`](hooks/stop-running-stack.sh): makes Claude stop the Docker containers
  it started before it finishes, so nothing keeps running and eating battery.
- [`stack-held-by-peer.sh`](hooks/stack-held-by-peer.sh): stops one Claude window from stopping
  Docker containers that another window is using.

### Keeps git tidy

- [`git-fetch-prune.sh`](hooks/git-fetch-prune.sh): keeps Claude's picture of GitHub up to date,
  in the background, so it does not act on old information.
- [`git-prune-gone-branches.sh`](hooks/git-prune-gone-branches.sh): deletes old branches when no
  work would be lost, and lists the ones it kept.
- [`git-submodule-update-after-switch.sh`](hooks/git-submodule-update-after-switch.sh): keeps
  submodules, repos inside a repo, in step after Claude switches branch.

### Keeps a record

- [`prompt-log.sh`](hooks/prompt-log.sh): saves every prompt you type, on your computer only, so
  commits and pull requests can quote the prompts behind them.
- [`prompts-md.sh`](hooks/prompts-md.sh): builds a `PROMPTS.md` file that lists those prompts per
  commit, like the one in this repo.
- [`no-meta-prompts.sh`](hooks/no-meta-prompts.sh): keeps prompts about Claude's own setup out of
  a project's history.
- [`usage-log.sh`](hooks/usage-log.sh): writes down the tokens each turn used, so you can add up
  a week later.

### Keeps Claude to the rules

- [`CLAUDE.md`](CLAUDE.md): the rules Claude follows in every project. It names no person or
  company, so you can copy it as it is.
- [`claude-md-changed.sh`](hooks/claude-md-changed.sh): tells a running session when the rules
  were changed in another window.
- [`prompt-feedback-box.sh`](hooks/prompt-feedback-box.sh): makes sure replies in the desktop app
  end with a short note on how your prompt could have been better.
- [`memory-plain-characters.sh`](hooks/memory-plain-characters.sh): points out long dashes in
  Claude's memory notes, so Claude swaps them for plain punctuation.
- [`share-memories.sh`](hooks/share-memories.sh): shares Claude's notes about a project with your
  team. It does nothing until you set it up.

### Extras

- [`settings.json`](settings.json): turns the hooks on, picks my model, blocks a few tools,
  leaves "Co-Authored-By: Claude" off commits and keeps old sessions for 90 days instead of 30.
- [`mods/session-usage`](mods/session-usage): a line under the prompt box that shows how many
  minutes the cache stays warm (a warm cache makes the next message cheaper), how full Claude's
  memory of the chat is, and what the session has cost so far.
- [`skills/pull-requests`](skills/pull-requests/SKILL.md): how Claude writes a pull request: the
  description, the steps to test it, screenshots.
- [`skills/slack-draft`](skills/slack-draft/SKILL.md): Claude drafts a Slack message and puts it
  on your clipboard with links and bold kept. You paste it and press send. Mac only.
- [`workflows/dream.js`](workflows/dream.js): type `/dream` when you stop for the day. Many
  agents read your recent sessions and your setup, and come back with suggested changes, each
  with a ready script. It changes nothing by itself and stops before your usage limits.
- [`agents/dream-worker.md`](agents/dream-worker.md): a lighter agent for `/dream`, so it uses
  fewer tokens.

### Only for this repo

- [`sync.sh`](sync.sh): keeps this copy and my own `~/.claude` the same, and checks that nothing
  private gets published. `--install` copies everything onto a new computer.
- [`test/dream-sim`](test/dream-sim/): checks how `/dream` spends your usage. Not installed.

For the full details, open the file: every hook explains itself at the top, and so do `sync.sh`
and `dream.js`.

## Before you install

- These are my rules, and some are taste: every reply ends with feedback on your prompt, no long
  dashes, commit messages quote the prompts behind them, pull requests open as drafts. Read
  `CLAUDE.md`, or ask Claude to sum it up, and delete what you do not want.
- I use this on a Mac. The hooks need `jq`, which macOS has built in, and some need `gh`,
  GitHub's own command-line tool.

## Install

1. Open Terminal and copy this repository to your computer:

   ```bash
   git clone https://github.com/lambdakilo/dotclaude.git ~/Projects/dotclaude
   ```

2. Pick one:

   a. Take only some pieces (recommended): open Claude Code and give it this prompt.

      ```text
      read ~/Projects/dotclaude/README.md and the files it links. explain in plain words what each piece would change for me, then copy only the ones i say yes to into ~/.claude and add their settings to my settings.json without removing anything of mine
      ```

   b. Take everything. Each of your own files that it replaces is kept next to it with `.bak` at
      the end, such as `~/.claude/settings.json.bak`.

      ```bash
      ~/Projects/dotclaude/sync.sh --install
      ```

3. Quit Claude Code and open it again, so it loads the new setup.

To get my later changes, update your copy and then do step 2 again:

```bash
git -C ~/Projects/dotclaude pull
```

## License

Prose, meaning `CLAUDE.md`, `PROMPTS.md`, `skills/pull-requests/SKILL.md`,
`skills/slack-draft/SKILL.md` and this README, is licensed under Creative Commons
Attribution-ShareAlike 4.0 International. See [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
