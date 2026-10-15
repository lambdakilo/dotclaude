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
- [`workflows/weekly.js`](workflows/weekly.js): a saved Claude Code workflow, run as
  `/weekly` when there are tokens left at the end of a week. It reads the week's session
  transcripts in batches, the whole configuration, `claude doctor`, the Claude Code changelog and
  Anthropic news since the last run, the user's own pull request reviews, and the skill repositories
  listed in `~/.claude/weekly-review/skill-repos.txt`, which stays local. Two more agents check
  each proposal, one that its evidence holds and one that no rule already covers it. The run
  writes one report to `~/.claude/weekly-review/` with habits for next week and a shell script
  for each change to the setup. It changes nothing itself. Between chunks of work it reads the
  plan usage card in the desktop app and stops adding sources and proposals before a limit would
  come within five points of full, estimating each chunk from what earlier runs cost. It keeps
  those costs in `~/.claude/weekly-review/usage-history.jsonl`, which stays local.
- [`sync.sh`](sync.sh): pulls this checkout, copies each mirrored file whichever way it changed,
  stops on a file changed on both sides, scans everything for private names, paths, addresses
  and credentials before anything gets committed, and after a clean scan copies every published
  file into the directories listed in `sync-mirrors.txt`. With `--install` it copies the
  mirrored files into `~/.claude` on a new machine.
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
