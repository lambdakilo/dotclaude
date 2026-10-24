# dotclaude

Claude Code is the AI that writes code for you, in a terminal or in the Claude desktop app. It
reads its setup from a hidden folder on your computer, `~/.claude`. This repository is a public
copy of my setup, so you can borrow from it.

Claude Code is good at writing code, but left alone it makes some of the same mistakes again and
again. Most of this setup stops those mistakes before they happen. [How I work](#how-i-work) shows
how I use it from day to day.

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
- **Eval**: a check that runs the same way every time and gives a score, so a change that makes
  things worse shows up.
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
- [`no-foreground-wait.sh`](hooks/no-foreground-wait.sh): stops Claude from checking over and over
  on a task it left running in the background, which keeps it from reading your messages for up to
  ten minutes.
- [`no-git-checkout.sh`](hooks/no-git-checkout.sh): stops Claude from using `git checkout`, which
  can overwrite files by mistake, and names the `git switch` or `git restore` command instead.
- [`calendar-free-busy-only.sh`](hooks/calendar-free-busy-only.sh): stops Claude from reading
  other people's calendar events. It can still see when they are free.
- [`slack-user-search-own-workspace.sh`](hooks/slack-user-search-own-workspace.sh): tells Claude
  that the Slack user search misses members of other companies who write in a shared channel, so it
  reads that channel instead of saying it cannot see their message.
- [`stop-running-stack.sh`](hooks/stop-running-stack.sh): makes Claude stop the Docker containers
  it started before it finishes, so nothing keeps running and eating battery.
- [`stop-unreachable-claim.sh`](hooks/stop-unreachable-claim.sh): sends Claude back to try the
  built-in browser, where you are signed in, before it says a page or file is out of reach.
- [`stack-held-by-peer.sh`](hooks/stack-held-by-peer.sh): stops one Claude window from stopping
  Docker containers that another window is using.

### Keeps git tidy

- [`git-fetch-prune.sh`](hooks/git-fetch-prune.sh): keeps Claude's picture of GitHub up to date,
  in the background, so it does not act on old information.
- [`git-fetch-before-remote-base.sh`](hooks/git-fetch-before-remote-base.sh): fetches first and
  waits when Claude is about to branch, rebase or reset from the copy on GitHub, so it never
  starts from an old one.
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
  or the pull request skill were changed in another window.
- [`permission-mode-changed.sh`](hooks/permission-mode-changed.sh): tells a running session when you
  switched its permission mode, so it never names the old one.
- [`prompt-feedback-box.sh`](hooks/prompt-feedback-box.sh): makes sure every reply to a prompt
  you typed ends with a short note on how your prompt could have been better.
- [`memory-plain-characters.sh`](hooks/memory-plain-characters.sh): points out long dashes in
  Claude's memory notes, so Claude swaps them for plain punctuation.
- [`claude-md-memory-index.sh`](hooks/claude-md-memory-index.sh): when Claude changes a rule in
  `CLAUDE.md`, shows it every memory note index, so it fixes the notes that still say the old
  thing.
- [`share-memories.sh`](hooks/share-memories.sh): shares Claude's notes about a project with your
  team. It does nothing until you set it up.

### Extras

- [`settings.json`](settings.json): turns the hooks on, picks my model, blocks a few tools,
  leaves "Co-Authored-By: Claude" off commits and keeps old sessions for 90 days instead of 30.
- [`mods/session-usage`](mods/session-usage): a line under the prompt box that shows how many
  minutes the cache stays warm (a warm cache makes the next message cheaper), how full Claude's
  memory of the chat is, and what the session has cost so far.
- [`presence`](presence/install.sh): my phone gets Claude's pushes, such as a question waiting for
  an answer, only while the Mac is locked. [`lock-listener.swift`](presence/lock-listener.swift)
  keeps the file that `CLAUDE_CLIENT_PRESENCE_FILE` in `settings.json` names in step with the screen
  lock: it is there while the screen is unlocked, and Claude Code skips the push then. Mac only.
  This builds it and starts it at every login:
  ```zsh
  ~/.claude/presence/install.sh
  ```
- [`skills/pull-requests`](skills/pull-requests/SKILL.md): how Claude writes a pull request: the
  description, the steps to test it, screenshots, and how it reviews one.
- [`skills/pull-requests/pane-upload.sh`](skills/pull-requests/pane-upload.sh): puts screenshots
  into a pull request from the app's built-in browser, which cannot upload files itself.
- [`skills/pull-requests/review-page`](skills/pull-requests/review-page/build.py): turns a pull
  request's test steps and screenshots into a checklist page you tick off with the keyboard while
  you review it.
- [`skills/slack-draft`](skills/slack-draft/SKILL.md): Claude drafts a Slack message and puts it
  on your clipboard with links and bold kept. You paste it and press send. Mac only.
- [`skills/dotclaude`](skills/dotclaude/SKILL.md): how Claude keeps this copy and my own `~/.claude`
  the same, and what it must never publish here. Claude reads it only before it changes the setup,
  which keeps the rules every session reads shorter.
- [`workflows/dream.js`](workflows/dream.js): type `/dream` when you stop for the day. Many
  agents read your recent sessions and your setup, and come back with suggested changes, each
  with a ready script. It changes nothing by itself and stops before your usage limits. When
  `~/.claude/dream/evals-checkout.txt` names a copy of this repository, it then reruns the evals
  below and publishes their numbers.
- [`agents/dream-worker.md`](agents/dream-worker.md): a lighter agent for `/dream`, so it uses
  fewer tokens.

### Only for this repo

- [`sync.sh`](sync.sh): keeps this copy and my own `~/.claude` the same, and checks that nothing
  private gets published. It also stops on a shell script with a syntax error, a file this list
  leaves out, or a line in `CLAUDE.md`, the pull request skill or this README wider than 100
  characters. `--install` copies everything onto a new computer.
- [`reflow.sh`](reflow.sh): rewraps the paragraphs an edit changed in `CLAUDE.md`, the pull request
  skill or this README at 100 characters, in this copy and in `~/.claude`.
- [`test/dream-sim`](test/dream-sim/): checks how `/dream` spends your usage. Not installed.
- [`test/hooks`](test/hooks/checks.mjs): feeds every hook the input Claude Code sends it, in a
  throwaway home folder, and checks what it lets through. Not installed.
- [`test/rules`](test/rules/adherence.mjs): counts how often Claude kept the rules in your own
  sessions of the last week. It prints counts only, never what was said.
- [`test/evals.mjs`](test/evals.mjs): runs all of these and fills in the Evals section below.

For the full details, open the file: every hook explains itself at the top, and so do `sync.sh`
and `dream.js`.

## How I work

This is how I use this setup from day to day, on a MacBook Air with an M5 chip. It leaves out what
I work on.

### Start of day

Each morning, before I start anything, I run `sod`, short for start of day, in a terminal:

```zsh
sod
```

It lives at `~/bin/sod`, and `~/bin` is on my `PATH`:

```zsh
#!/bin/zsh
set -euo pipefail

if docker info >/dev/null 2>&1; then
  docker ps -q | xargs docker stop
  docker container prune -f
  docker volume prune -af
fi

brew update
brew upgrade -y
brew cleanup
```

If Docker is running, it stops every container and deletes the containers and all their volumes,
so each project starts the day from fresh test data and nothing from yesterday keeps running.
Anything I changed by hand in a local database is gone. Then it updates Homebrew and everything
Homebrew installed, without asking, and removes the old versions.

### Prompting

I work in the Code tab of the Claude desktop app, one session per task, started in the project's
folder under `~/Projects`. Sessions run in auto mode, so Claude does not ask before every command,
and [`settings.json`](settings.json) picks the model and the effort.

I write prompts the way I would message a colleague: short, lowercase, typos left in. "start doing
issue 123" or "review pr 123" is a whole prompt. Claude reads the issue, the code and its notes,
and asks me only what is mine to decide, as a question with its recommended answer first. Most of
my follow-ups are a word or a click: "go", "shorter", "commit and push", or a button in the box
Claude leaves at the end of its turn. A follow-up that is a task of its own, Claude offers as a
new session I can start with one click.

Two habits do most of the work:

- When Claude does something that should never happen again, I put `dotclaude` in the prompt, as
  in "dotclaude fix. next time ...". Claude writes the rule into [`CLAUDE.md`](CLAUDE.md) or a
  skill, runs [`sync.sh`](sync.sh), and commits and pushes it here with my prompt quoted. Many of
  the rules here started that way.
- Every reply ends with a short Prompt feedback section: what my prompt left out, and a rewrite.
  I read it and write the next prompt better.

### Browsers

Firefox is my default browser, so the links Claude gives me, such as a pull request or a page it
made, open there. Claude does its own browsing in the browser built into the desktop app, the pane
beside the chat, where I sign in once to the sites it needs. Claude in Chrome is blocked in
`settings.json`, so Claude never drives a browser I am using.

### Battery and sleep

The Air spends nights on its charger while Claude works, so it never charges past 80%. I set this
once:

1. Open System Settings and click Battery in the sidebar.
2. Click the info button next to Charging, set Charge Limit to 80%, and click Done.

Charge Limit needs macOS Tahoe 26.4 or later and a Mac with Apple silicon, as
[Apple's support page](https://support.apple.com/102338) says.

Nothing may put the Mac to sleep while Claude works. In the Claude app, Settings > Claude Code has
"Keep computer awake while Claude works" and "Keep awake on battery power", and both are on. macOS
itself never sleeps on a timer:

```zsh
sudo pmset -a sleep 0 disksleep 0
```

The display still turns off after 3 minutes:

```zsh
sudo pmset -a displaysleep 3
```

I also veto sleep altogether, so a long run is never cut short. The cost is that the Air stays
awake on battery too, until I shut it down:

```zsh
sudo pmset -a disablesleep 1
```

This shows what is in effect:

```zsh
pmset -g
```

### Dreaming at the weekend

The weekly limit of my Claude plan resets on Saturday afternoon. [`/dream`](workflows/dream.js)
reads the reset time from the usage card in the app and picks its mode by itself, so I run it
twice around the reset:

1. Friday, when I get home: connect the charger, leave the Claude app open, and send this in a new
   Code session.

   ```text
   /dream
   ```

   On the day before the reset this is an eve run. It spends most of what is left of the week
   overnight, but keeps back two 5-hour windows, one for my work on Saturday and one for the
   final run, and leaves the 5-hour window that would be open at 08:00 on Saturday untouched.

2. Saturday: open that session. It goes through what it proposes one question at a time, each
   with the exact change, a moment where things went wrong and how that moment goes once the
   change is in. I answer "Add it" or "Not now", and Claude applies what I added and pushes it
   here. Then I carry on with my own work.

3. Saturday, when I am done: connect the charger again and send `/dream` in a new Code session.
   On the reset day this is a final run. It spends the rest of the week, down to 1 percentage
   point, and stops starting work an hour and a quarter before the reset, so everything reports
   back in time.

4. The next time I sit down: open that session and go through its proposals the same way.

## Evals

These are the numbers from the last `/dream` run, or from the last time I ran the evals by hand.
The rule counts come from my own sessions, and only the counts leave my computer. To run the
evals on your copy:

```bash
node ~/Projects/dotclaude/test/evals.mjs
```

<!-- evals:start -->
| Suite | What it checks | Result |
| --- | --- | --- |
| [Hook tests](test/hooks/checks.mjs) | every hook, fed the input Claude Code sends it | 169 of 169 pass |
| [Dream simulation](test/dream-sim/checks.mjs) | how `/dream` spends usage and when it stops | 49 of 49 pass |
| [Usage mod tests](mods/session-usage/hooks/register.test.ts) | the line under the prompt box | 4 of 4 pass |

How often Claude kept rules from [`CLAUDE.md`](CLAUDE.md) from 2026-10-17 to 2026-10-24, in 68 of my own sessions and the commits of the 6 repositories they worked in, counted by [`test/rules/adherence.mjs`](test/rules/adherence.mjs):

| Rule | Kept |
| --- | --- |
| No long dashes in replies | 99% (270 of 271 replies) |
| Plain quotes, arrows and dots in replies | 99% (270 of 271 replies) |
| A Prompt feedback section after each typed prompt | 91% (222 of 242 replies) |
| Commit message lines within 72 columns | 99% (336 of 337 commits) |
| No Claude attribution in commits | 100% (337 of 337 commits) |
<!-- evals:end -->

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

## License

Prose, meaning `CLAUDE.md`, `PROMPTS.md`, every `SKILL.md` under `skills/` and this README, is
licensed under Creative Commons Attribution-ShareAlike 4.0 International. See
[`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
