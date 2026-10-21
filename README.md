# dotclaude

This is a public mirror of my `~/.claude`, the global configuration directory of Claude Code: the
rules I have Claude Code follow in every project, my user settings, my hooks, a skill and a
workflow, with the script I use to keep this checkout and the live directory in sync.

The rules file names no person, organisation, customer or repository, so it can be copied as it
stands. `./sync.sh --install` copies every mirrored file into your own `~/.claude`.

## Files

- [`CLAUDE.md`](CLAUDE.md): the rules Claude Code follows in every project, installed as
  `~/.claude/CLAUDE.md`.
- [`settings.json`](settings.json): my user settings, installed as `~/.claude/settings.json`:
  model and effort level, the Figma plugin turned off by default and with its writing tools
  denied, Claude in Chrome denied, the hooks below, no Claude attribution on commits or pull
  requests, session transcripts kept for 90 days instead of 30, so `/dream` has more
  history to read, and the folder of the session-usage mod below.
- [`hooks/git-fetch-prune.sh`](hooks/git-fetch-prune.sh): runs on every prompt and fetches all
  remotes with pruning in the background, at most once per 15 minutes per repository, without
  ever prompting for credentials.
- [`hooks/git-prune-gone-branches.sh`](hooks/git-prune-gone-branches.sh): runs when a session
  starts, fetches with pruning, then deletes the local branches whose remote branch is gone when
  nothing on them would be lost, that is when every commit is on the default branch or the
  branch is the head of a pull request GitHub still holds. Other gone branches are named for the
  user to decide. Deleted names and hashes are logged in the git directory for recovery.
- [`hooks/git-submodule-update-after-switch.sh`](hooks/git-submodule-update-after-switch.sh):
  runs after every Bash command that switches branches and, in a repository with submodules,
  runs `git submodule update --init` and reports `git submodule status` to Claude Code, since a
  switch moves the pin of each submodule in the index but leaves its work tree where it was.
- [`hooks/check-not-piped.sh`](hooks/check-not-piped.sh): runs before every Bash command and
  refuses a check, such as verify, tests, lint, a build or end to end, piped into another
  command, since a pipeline exits with its last command's status and a failed check piped into
  `tail` reads as a pass. It lets the command through when it sets `pipefail`, and otherwise
  names the way round: the output to a file in the scratchpad, then the status echoed.
- [`hooks/no-home-search.sh`](hooks/no-home-search.sh): runs before every Bash command and
  refuses a search that walks the whole disk or the home folder: `find`, `fd`, `rg`, `du`,
  `tree`, `grep -r` or `ls -R` rooted at `/`, `/Users`, `/Volumes`, `~` or `~/*`, and `mdfind`
  without `-onlyin`. macOS asks the user about each protected folder such a search reaches, and
  the command waits for the answer. The refusal names the folders to search instead.
- [`hooks/cd-fall-through.sh`](hooks/cd-fall-through.sh): runs before every Bash command and
  refuses one in which a part after a `;` or a line break would still run when a `cd` before it
  failed, and so would run in the start directory. A `cd` guarded with `|| exit`, or into a
  directory that exists already, goes through.
- [`hooks/prompt-log.sh`](hooks/prompt-log.sh): runs on every prompt and appends it to
  `~/.claude/prompt-log/<session id>.jsonl`, which stays local. With `print` it prints the
  session's prompts numbered and quoted for a pull request body, or with `--commit` for a commit
  message, with URLs and email addresses replaced by `[pasted: an address]`.
- [`hooks/memory-plain-characters.sh`](hooks/memory-plain-characters.sh): runs after every
  Write, Edit and Bash call and hands back each em dash in a memory file changed in the last two
  minutes, since the built-in memory template puts one in every index line.
- [`hooks/share-memories.sh`](hooks/share-memories.sh): runs after every Write, Edit and Bash
  call and shares project memory with colleagues. An untracked `shared-memories.conf` beside the
  hooks folder names a clone of a shared repository, the GitHub owners whose repositories are
  shared and your handle. In such a repository, once a memory note has changed, it copies every
  note without `share: no` into `<repository>/<handle>/` of that clone, then commits and pushes in
  the background. It leaves out a note that looks like it holds a password or token and names it.
  Without the conf file it does nothing.
- [`hooks/claude-md-changed.sh`](hooks/claude-md-changed.sh): keeps a copy of `CLAUDE.md` for
  each session and, once the file has changed, adds the diff to the next prompt, or blocks the
  next commit or `gh pr` create, edit or merge once with the diff, so a session sees rule edits
  made from another session while it runs.
- [`hooks/no-github-posts.sh`](hooks/no-github-posts.sh): runs before every shell command and
  refuses the GitHub CLI calls that would post as the user: `gh pr comment`, `gh issue comment`,
  `gh pr review`, a close or reopen with `--comment`, and `gh api` calls that write a comment or a
  review, reply to a review thread or resolve one. It runs in every permission mode, bypass
  included. Editing a PR body, assigning, and closing or reopening without a comment still work.
- [`hooks/prompt-feedback-box.sh`](hooks/prompt-feedback-box.sh): runs before the desktop app's
  next-step box and on every prompt. A box with a question ends the turn and takes no text after
  it, so in a turn a typed prompt opened, it refuses such a box once until a `Prompt feedback`
  section is written. On a prompt that repeats a reply button of the last box, it tells Claude
  Code that it wrote those words itself, so the section is left out.
- [`hooks/no-meta-prompts.sh`](hooks/no-meta-prompts.sh): runs before every shell command and
  blocks a commit or a `gh pr` create, edit or merge once when a prompt it quotes has a sentence
  that opens with `dotclaude`, `global ruling`, `global memory` or `memory:`, the words that mark
  an ask about the Claude Code setup, so such asks stay out of the history of a project. This
  checkout and its mirrors are let through, and so is the same command run again.
- [`hooks/prompts-md.sh`](hooks/prompts-md.sh): not a hook but a script, run before a commit in
  a repository with a `PROMPTS.md` at its root. It rebuilds that file from the prompts section of
  every commit message, newest first, each with its commit and pull request, and with
  `--message <file>` lists the commit about to be made first. A commit cannot name its own hash,
  so that one links to the file's history until the next rebuild.
- [`mods/session-usage`](mods/session-usage): a Claude Code mod named `usage`, the label the app
  puts before its line, installed as `~/.claude/mods/session-usage` and loaded in every session
  through `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`. It pins a short status line under the
  prompt, such as `🔥 47 min, 16% ctx, 6.1M, $2.96`: how many minutes the prompt cache stays
  warm, how full the context window is, and the tokens the session has processed and what they
  would cost at the API list prices. Once the cache is cold the line opens with
  `🧊 since 12:22`, or with `🧊 since 19 Oct` from the next day on. The mod API draws a status
  line as plain text, so the emoji stand in for colours. The desktop app shows about 40
  characters before it cuts the line, so the cache comes first. The figures refresh after every
  turn and every 15 seconds while one runs; between turns the minutes count down without the
  transcript being read again. The app draws the line, and it never enters the model's context. `usage.sh` reads
  the transcript, which repeats a response's usage on every streamed block, so it counts each
  response once. The status line leaves out workflow agents, whose transcripts can run to
  hundreds of megabytes; `usage.sh --run <folder>` totals every transcript under a folder, such
  as a workflow run's, by kind of token and by model, with the share of prompt tokens the warm
  cache served and an estimate of the energy the responses took and the CO2e it emitted, and
  the dream workflow has the session show it after every run. `usage.sh --since <time>
  [<until>]` totals the same from the usage log for any period, all sessions together. The
  energy is the seconds each response streamed times one request's share of an 8-GPU H100 node,
  about 0.75 kW, as [How Hungry is AI?](https://arxiv.org/abs/2505.09598) models a flagship
  model. The CO2e uses the
  [Ember 2025 grid average](https://ourworldindata.org/grapher/carbon-intensity-electricity) of
  the US when the response's `inference_geo` is `us`, and of the world otherwise. It is an order
  of magnitude, not a measurement: it leaves out idle capacity, training and hardware
  manufacture, and production serving likely batches more than the paper's 8 requests. The mod
  API is early access and may change between Claude Code releases.
- [`hooks/usage-log.sh`](hooks/usage-log.sh): a `Stop` hook that after every turn appends one
  line per new model response of the session and its agents to
  `~/.claude/usage-log/<YYYY-MM>.jsonl`: its time, model, tokens by kind, the seconds it ran and
  its `inference_geo`, so a week can be totalled after `cleanupPeriodDays` has deleted the
  transcripts. It reads a transcript again only when it has grown. Run it once with `--all` to
  fill the log from every transcript kept:
  ```sh
  ~/.claude/hooks/usage-log.sh --all
  ```
- [`skills/pull-requests/SKILL.md`](skills/pull-requests/SKILL.md): a skill, installed as
  `~/.claude/skills/pull-requests/SKILL.md`, with the procedures for a pull request: the body and
  its prompts block, the steps to verify it, the reply to a review, and screenshots and
  recordings. `CLAUDE.md` tells Claude Code to load it before any of those, so the procedures stay
  out of the context of sessions that never touch a pull request.
- [`skills/slack-draft/SKILL.md`](skills/slack-draft/SKILL.md) and
  [`copy-rich.sh`](skills/slack-draft/copy-rich.sh): a skill for drafting a Slack message the user
  pastes and sends. Slack's message box makes no link from `[text](url)`, so the skill writes the
  draft as HTML with pinned links to commits, file lines, Figma frames and messages, and the
  script puts it on the macOS clipboard as HTML, RTF and plain text and reads each back, so one
  paste keeps link text, bold and lists.
- [`workflows/dream.js`](workflows/dream.js): a saved Claude Code workflow, run as `/dream` in idle
  time, at the end of a day, overnight or over a weekend. Its work comes in four tiers, and each
  tier's findings are merged and checked before later tiers get the usage: first the proposals an
  earlier run had no usage to check, the session transcripts used since the last run, by their last
  user or assistant record and newest first, the whole configuration and the user's own pull
  request reviews; then whether each section of `CLAUDE.md` is followed, broken or never triggered,
  where sessions waste tokens, `claude doctor`, the Claude Code changelog, the Claude Platform
  release notes and Managed Agents docs, such as dreams, for what the setup or this workflow could
  use, Anthropic news, what Claude Code now does by itself that the setup duplicates, and the skill
  repositories listed in `~/.claude/dream/skill-repos.txt`, which stays local; then an audit of
  each repository worked in against its `CLAUDE.md` and project memory, a review of the shared
  repository `shared-memories.conf` names, for the user's shared notes to trim or keep private and
  notes that disagree with a colleague's, a review of the user's open
  pull requests in repositories checked out under `~/Projects` or updated in the last two weeks,
  and a brief for Monday; and last subagent transcripts and older transcripts a week at a time.
  Transcripts and configuration run every time, reviews once a day and the rest once a week. Two
  more agents check each new proposal, one that its evidence holds and one that no rule already
  covers it, and open proposals carry over in `~/.claude/dream/backlog.json` until they are applied
  or found obsolete. Each run writes a report short enough to read in the chat and a folder with a
  shell script per change, numbered in the order to apply them and tested in that order in a
  sandbox. It changes nothing itself. Its result tells the calling session to show the whole
  report, check the usage limits against the run's target and say why the run stopped there, then
  ask about each change on its own: the exact text it adds, a real moment from the transcripts that
  went wrong, and the same moment with the change in place. A change the user adds is applied
  before the next question, one put off comes back a week later, and the session commits what
  changed. `/dream review` skips the run and asks the same way about what the backlog still holds
  open, for a dialogue that stopped early. A run keeps seven pieces of work going, reads the plan
  usage card in the desktop app as they finish, and starts new work only while it fits, estimating
  each piece from what earlier runs cost, as kept in `~/.claude/dream/usage-history.jsonl`, and
  holds back the checks of what it reads. Transcripts and proposals it had no usage for carry over
  to the next run. Its last usage reading goes into `~/.claude/dream/weekly-usage.jsonl`, so the
  last line for a week keeps how much of it was used, and the report ends with this week, last week
  and the 4-week and 52-week averages from it. Run bare, it picks its mode from the weekly reset.
  On the day before, it spends the week but keeps back what two 5-hour windows cost, one for work
  and one for a last run, and stops in time to leave the 5-hour window open at 08:00 on the reset
  day untouched. On the reset day it spends the week down to one point and stops starting work
  before the reset, so its agents finish first. Every run stops just short of the 5-hour limit,
  since an agent that reaches it fails instead of waiting for the reset, and says when another run
  could spend what the week has left. The backlog is merged on disk with jq, and the scripts are
  written and tested a few proposals at a time, within the same usage guard. `mode`, `workAt`,
  `keep` and `margin` change those choices, and `day` keeps the margin free on the 5-hour limit
  while the user works.
- [`test/dream-sim/`](test/dream-sim/): a simulation of dream runs with fake agents, a clock and
  both usage windows, which checks how each mode spends and stops. It stays in this checkout and
  is not installed:
  ```sh
  (cd ~/Projects/dotclaude && node test/dream-sim/checks.mjs)
  ```
- [`agents/dream-worker.md`](agents/dream-worker.md): the agent type every agent of `/dream`
  runs as. Its tools line names only the tools those agents use, so they start without the
  browser, simulator and artifact tools of the desktop app, about half of each first request.
- [`sync.sh`](sync.sh): pulls this checkout, copies each mirrored file whichever way it changed,
  a JSON file in the key order it has here, stops on a file changed on both sides, scans
  everything for private names, paths, addresses and credentials before anything gets committed,
  and after a clean scan copies every published file into the directories listed in
  `sync-mirrors.txt`, removing there what this checkout has deleted. With
  `--commit <message-file>` it then commits and pushes this checkout and every mirror with that
  message, adding to a mirror's message a line that names the commit here. With `--install` it
  copies the mirrored files into `~/.claude` on a new machine.
- `sync-allow.txt`: optional and absent here, one literal per line that the scan ignores.
- `sync-deny.txt`: optional and ignored by git, one literal per line that fails the scan in any
  case, such as a private project's names and labels. `./sync.sh --check-message <file>` checks
  a commit message against it, for a commit-msg hook.
- `sync-mirrors.txt`: optional and ignored by git, one directory per line that gets a copy of
  every published file, for a second copy kept in another repository. A leading `~/` stands for
  the home directory.
- [`PROMPTS.md`](PROMPTS.md): every prompt behind the commits of this repository with its commit,
  written by `hooks/prompts-md.sh`, which `sync.sh` runs before the scan.
- [`LICENSE`](LICENSE) and [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0): the licence texts,
  see below.

## License

Prose, meaning `CLAUDE.md`, `PROMPTS.md`, `skills/pull-requests/SKILL.md`,
`skills/slack-draft/SKILL.md` and this README, is
licensed under Creative Commons Attribution-ShareAlike 4.0 International. See
[`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
