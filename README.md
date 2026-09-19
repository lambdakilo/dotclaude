# .claude

One developer's global Claude Code configuration, published so other people can read how the
workflow is set up and copy what they find useful.

- `CLAUDE.md` is the rules file loaded into every session, from `~/.claude/CLAUDE.md`.
- `settings.json` is the user settings file, from `~/.claude/settings.json`.
- `hooks/git-fetch-prune.sh` is a `UserPromptSubmit` hook that keeps remote-tracking refs fresh.
- `sync.sh` copies those files in from `~/.claude` and refuses to publish a name, a home path,
  an email address or a credential.

Commit messages quote the prompts that led to each change.

Clone this into a directory that is not named `.claude` when a Claude Code session might start
in its parent, because Claude Code reads a `.claude` directory under the working directory as
that project's configuration.

## License

Code, meaning the shell scripts and `settings.json`, is licensed under the GNU Affero General
Public License, version 3 or (at your option) any later version. See [`LICENSE`](LICENSE).

Prose, meaning `CLAUDE.md` and this README, is licensed under Creative Commons
Attribution-ShareAlike 4.0 International. See [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

SPDX identifiers: `AGPL-3.0-or-later` for code, `CC-BY-SA-4.0` for prose.
