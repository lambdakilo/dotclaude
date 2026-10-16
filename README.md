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
  denied, the hooks below, no Claude attribution on commits or pull requests, and session
  transcripts kept for 90 days instead of 30, so `/dream` has more history to read.
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
- [`hooks/prompt-log.sh`](hooks/prompt-log.sh): runs on every prompt and appends it to
  `~/.claude/prompt-log/<session id>.jsonl`, which stays local. With `print` it prints the
  session's prompts numbered and quoted for a pull request body, or with `--commit` for a commit
  message, with URLs and email addresses replaced by `[pasted: an address]`.
- [`hooks/memory-plain-characters.sh`](hooks/memory-plain-characters.sh): runs after every
  Write, Edit and Bash call and hands back each em dash in a memory file changed in the last two
  minutes, since the built-in memory template puts one in every index line.
- [`hooks/claude-md-changed.sh`](hooks/claude-md-changed.sh): keeps a copy of `CLAUDE.md` for
  each session and, once the file has changed, adds the diff to the next prompt, or blocks the
  next commit or `gh pr` create, edit or merge once with the diff, so a session sees rule edits
  made from another session while it runs.
- [`hooks/no-github-posts.sh`](hooks/no-github-posts.sh): runs before every shell command and
  refuses the GitHub CLI calls that would post as the user: `gh pr comment`, `gh issue comment`,
  `gh pr review`, a close or reopen with `--comment`, and `gh api` calls that write a comment or a
  review, reply to a review thread or resolve one. It runs in every permission mode, bypass
  included. Editing a PR body, assigning, and closing or reopening without a comment still work.
- [`skills/pull-requests/SKILL.md`](skills/pull-requests/SKILL.md): a skill, installed as
  `~/.claude/skills/pull-requests/SKILL.md`, with the procedures for a pull request: the body and
  its prompts block, the steps to verify it, the reply to a review, and screenshots and
  recordings. `CLAUDE.md` tells Claude Code to load it before any of those, so the procedures stay
  out of the context of sessions that never touch a pull request.
- [`workflows/dream.js`](workflows/dream.js): a saved Claude Code workflow, run as `/dream` in
  idle time, at the end of a day, overnight or over a weekend. Its work comes in four tiers, and
  each tier's findings are merged and checked before later tiers get the usage: first the session
  transcripts since the last run, newest first, the whole configuration and the user's own pull
  request reviews; then whether each section of `CLAUDE.md` is followed, broken or never
  triggered, where sessions waste tokens, `claude doctor`, the Claude Code changelog, the Claude
  Platform release notes and Managed Agents docs, such as dreams, for what the setup or this
  workflow could use, Anthropic news, what Claude Code now does by itself that the setup
  duplicates, and the skill repositories listed in `~/.claude/dream/skill-repos.txt`, which
  stays local; then an audit of
  each repository worked in against its `CLAUDE.md` and project memory, a review of the user's
  open pull requests and a brief for Monday; and last subagent transcripts and older transcripts
  a week at a time. Transcripts and configuration run every time, reviews once a day and the rest
  once a week. Two more agents check each new proposal, one that its evidence holds and one that
  no rule already covers it, and open proposals carry over in `~/.claude/dream/backlog.json` until
  they are applied or found obsolete. Each run writes a report short enough to read in the chat
  and a folder with a shell script per change, numbered in the order to apply them and tested in
  that order in a sandbox. It changes nothing itself. It keeps seven pieces of work going, reads
  the plan usage card in the desktop app as they finish, and starts new work only while it fits,
  estimating each piece from what earlier runs cost, as kept in
  `~/.claude/dream/usage-history.jsonl`. Transcripts it had no usage for carry over to the next
  run. Run bare, it picks its mode from the weekly reset. On the day before, it spends the week
  but keeps back what two 5-hour windows cost, one for work and one for a last run, and stops in
  time to leave the 5-hour window open at 08:00 on the reset day untouched. On the reset day it
  spends the week down to one point and stops starting work before the reset, so its agents
  finish first. On other days it guards only the weekly limits, letting the 5-hour limit fill and
  waiting for its reset. `mode`, `workAt`, `keep` and `margin` change those choices, and `day`
  keeps the 5-hour limit under the margin while the user works.
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
- [`LICENSE`](LICENSE) and [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0): the licence texts,
  see below.

## License

Prose, meaning `CLAUDE.md`, `skills/pull-requests/SKILL.md` and this README, is licensed under
Creative Commons Attribution-ShareAlike 4.0 International. See
[`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
