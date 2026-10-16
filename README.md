# dotclaude

This is a public mirror of my `~/.claude`, the global configuration directory of Claude Code: the
rules I have Claude Code follow in every project, my user settings, my hooks and a workflow, with
the script I use to keep this checkout and the live directory in sync.

The rules file names no person, organisation, customer or repository, so it can be copied as it
stands. `./sync.sh --install` copies every mirrored file into your own `~/.claude`.

## Files

- [`CLAUDE.md`](CLAUDE.md): the rules Claude Code follows in every project, installed as
  `~/.claude/CLAUDE.md`.
- [`settings.json`](settings.json): my user settings, installed as `~/.claude/settings.json`:
  model and effort level, the Figma plugin turned off by default and with its writing tools
  denied, the hooks below, and no Claude attribution on commits or pull requests.
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
- [`workflows/dream.js`](workflows/dream.js): a saved Claude Code workflow, run as `/dream` in
  idle time, at the end of a day, overnight or over a weekend. It reads the session transcripts
  since the last run in batches, the whole configuration, `claude doctor`, the Claude Code
  changelog and Anthropic news, the user's own pull request reviews, what Claude Code now does by
  itself that the setup duplicates, and the skill repositories listed in
  `~/.claude/dream/skill-repos.txt`, which stays local. Transcripts and configuration run every
  time, reviews once a day and the rest once a week. Two more agents check each new proposal, one
  that its evidence holds and one that no rule already covers it, and open proposals carry over
  in `~/.claude/dream/backlog.json` until they are applied or found obsolete. Each run writes a
  report short enough to read in the chat and a folder with a shell script per change, numbered
  in the order to apply them and tested in that order in a sandbox. It changes nothing itself.
  Between chunks of work it reads the plan usage card in the desktop app and stops adding work
  before a limit would come within five points of full, estimating each chunk from what earlier
  runs cost, as kept in `~/.claude/dream/usage-history.jsonl`. By default it guards only the
  weekly limits, letting the 5-hour limit fill and waiting for its reset, since it runs while the
  user is away. With `day` it keeps the 5-hour limit under the margin too.
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

Prose, meaning `CLAUDE.md` and this README, is licensed under Creative Commons
Attribution-ShareAlike 4.0 International. See [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
