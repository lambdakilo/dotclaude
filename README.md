# dotclaude

This is a public mirror of my `~/.claude`, the global configuration directory of Claude Code: the
rules I have Claude Code follow in every project, my user settings and my hooks, with the script I
use to keep this checkout and the live directory in sync.

The rules file names no person, organisation, customer or repository, so it can be copied as it
stands. The rest of this page says what each file does and how to install them.

## Layout

`~/.claude` is not a git checkout. Beside the files here it holds memory, session transcripts,
plugins and credentials, none of which belong in public. So this repository mirrors a chosen
subset instead: three files that exist both here and in `~/.claude`, at the same relative path,
with `sync.sh` keeping the two copies identical. Everything else in the checkout exists only here.

| File | Copy in `~/.claude` | What it does |
| --- | --- | --- |
| [`CLAUDE.md`](CLAUDE.md) | `~/.claude/CLAUDE.md` | The rules Claude Code follows in every project. |
| [`settings.json`](settings.json) | `~/.claude/settings.json` | My user settings: model, effort, permissions, plugins, hooks. |
| [`hooks/git-fetch-prune.sh`](hooks/git-fetch-prune.sh) | `~/.claude/hooks/git-fetch-prune.sh` | Fetches and prunes every remote in the background when a prompt is submitted. |
| [`sync.sh`](sync.sh) | none | Moves changes between `~/.claude` and this checkout, then scans for anything private. |
| `sync-allow.txt` | none | Optional and absent here: literals the scan may ignore. |
| [`README.md`](README.md) | none | This page. |
| [`LICENSE`](LICENSE) | none | GNU Affero General Public License, version 3, for the scripts and settings. |
| [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0) | none | Creative Commons Attribution-ShareAlike 4.0, for the prose. |

The pieces fit together like this. The rules file says how Claude Code should behave. The
settings file enforces the parts of that which can be enforced mechanically, and registers the
hook. The hook does the fetching the rules ask for. The sync script moves all three between the
two places and keeps private values out of the checkout.

## `CLAUDE.md`

Claude Code reads `~/.claude/CLAUDE.md` at the start of every session, whatever directory the
session was started from, and follows it as standing instructions. Project instructions and
memory are keyed to the start directory, so this file is where a rule goes when it should hold
everywhere.

Its sections, in order:

- **Git identity and attribution.** Never override the configured git author. Never add a
  Claude or Anthropic trailer to a commit, pull request or issue. When squashing, credit every
  human whose commits are squashed with a `Co-authored-by` trailer.
- **Remote state.** Fetch all remotes with pruning before any decision that depends on what the
  remote holds. The hook below is the safety net, not a substitute.
- **Git commands.** Use `git switch` to change and create branches, and reach for `git checkout`
  only for what `switch` and `restore` cannot do.
- **Commit messages.** Every line wrapped at 72 columns. Subject and body first, then a section
  that names the model and effort level and quotes, verbatim, the prompts that led to the
  commit, with a list of the abbreviations they use. Pasted text is replaced by a bracketed
  description. The history of this repository shows the format.
- **Pull requests.** Open them as drafts. The body starts with two collapsed blocks, the rules
  file in full and the prompts behind the pull request, followed by the repository's own
  template filled in. Fork checkouts branch from `upstream`, push to `origin` and open the pull
  request against the upstream repository. Direct checkouts keep one draft pull request at a
  time.
- **Prose.** No em or en dashes, no semicolons as connectors. Organisations by their full name,
  never "we". Any command the reader should run goes in its own fenced code block.
- **Prompt feedback.** Every reply ends with a short note on how the prompt could have been
  better, or one line saying it could not.
- **Comments.** Match the density of the surrounding code. Comment only what the code cannot
  say. Reasoning meant to persuade a reviewer goes in the commit message, not in the source.
- **Running things.** Run the repository's lint, typecheck and tests after meaningful edits.
  Leave nothing running at the end of a turn. Never run deployment tooling against a remote
  environment.
- **Public configuration repository.** How this mirror is maintained: which files are mirrored,
  what `sync.sh` does, and that a change to a mirrored file is synced, committed and pushed in
  the same turn.
- **Memory hygiene.** Memory is per start directory, so a rule that holds everywhere lives in
  this file, not in memory.

Mirrored files keep their names and relative paths, so `sync.sh` can compare and copy them
without a mapping. For this file that has a side effect: Claude Code also reads a `CLAUDE.md` at
a repository root as project instructions, so a session started inside this checkout would load
the same rules twice. The `claudeMdExcludes` entry in `settings.json` prevents that.

## `settings.json`

Claude Code's user-level settings. They apply in every project, underneath any project-level
settings. Key by key:

- **`attribution`.** Both `commit` and `pr` are empty strings, so Claude Code adds no
  "Co-Authored-By" or "Generated with" line to commits or pull requests. This backs the
  attribution rule in `CLAUDE.md` mechanically.
- **`permissions.deny`.** Tools Claude Code may never call. All of them are the Figma plugin's
  writing tools: anything that creates or edits a Figma file, uploads assets, or runs a
  generative plugin, shader or Weave tool. Reading tools stay allowed, so Claude can read a
  design but never change one. Each tool is listed twice because the server's tools can appear
  under `mcp__plugin_figma_figma__` or `mcp__figma__`, depending on how the server was
  registered.
- **`model`.** `claude-fable-5-1[1m]`, meaning Fable 5.1 with the one-million-token context
  window.
- **`enabledPlugins`.** The Figma plugin from the official plugin marketplace.
- **`modelSettings`.** Per-model settings. Fable 5.1 runs at effort level `xhigh`. The entry for
  Opus 5 is empty, so it runs with defaults. The commit message and pull request rules in
  `CLAUDE.md` take the effort level from here.
- **`theme`.** Dark.
- **`hooks`.** One `UserPromptSubmit` hook, the script under `hooks/`. It is registered as
  `async`, so a prompt is never held up by it, with a timeout of two minutes. The command path
  goes through `$HOME`, so the entry works unchanged on any machine.
- **`claudeMdExcludes`.** Glob patterns of `CLAUDE.md` files that Claude Code must not load as
  project instructions. The one pattern here matches this checkout's copy of the rules file.
- **`skipWorkflowUsageWarning`.** Skips the warning Claude Code shows before running a
  multi-agent workflow, which can use a large number of tokens.

The file carries my own choices. Read it before installing it and keep the values you want.

## `hooks/git-fetch-prune.sh`

The only hook so far. It is a `UserPromptSubmit` hook: Claude Code runs it every time a prompt is
submitted, before the model sees the prompt. This one keeps remote-tracking refs fresh, so that
a decision based on them, such as whether a branch was merged or where the default branch is, is
not made on stale data. In order, it:

1. Exits at once unless the project directory is inside a git repository that has at least one
   remote. Claude Code passes the project directory in `CLAUDE_PROJECT_DIR`.
2. Looks for a stamp file, `claude-code-fetch.stamp`, in the repository's common git directory,
   which the worktrees of one repository share. If the stamp is younger than the interval, 15
   minutes unless `CLAUDE_GIT_FETCH_INTERVAL_MINUTES` says otherwise, it exits. Otherwise it
   touches the stamp before fetching, so that two prompts in quick succession do not both fetch.
3. Runs `git fetch --all --prune` with every credential prompt disabled: no terminal prompt, an
   askpass helper that returns nothing, and SSH in batch mode. A missing key or an expired token
   makes the fetch fail quietly instead of hanging.
4. Prints nothing and always exits zero. Whatever a `UserPromptSubmit` hook prints is added to
   the model's context, and a failed fetch is not worth reporting on every prompt.

## `sync.sh`

The script that keeps the mirrored files identical in both places. It lives only in the
checkout. It reads the configuration directory from `CLAUDE_CONFIG_DIR`, falling back to
`~/.claude`, and finds the checkout from its own location, so it can be run from anywhere.

Run without arguments, it:

1. **Pulls** the checkout fast-forward. If the pull fails, because the machine is offline or the
   branch has diverged, it says so and goes on against the local commit.
2. **Reconciles** each mirrored file between `~/.claude` and the checkout. A file missing from
   `~/.claude` is installed from the checkout. A file the pull did not touch but that differs
   locally is copied into the checkout: a local edit, by hand or by a Claude Code session, wins.
   A file the pull changed, whose local copy still matches the version before the pull, is
   installed locally: the pulled edit wins. A file changed on both sides is left alone and
   reported for a manual merge.
3. **Scans** everything that would be published, meaning every tracked file and every untracked
   file git does not ignore, except the licence texts and `sync-allow.txt`, for values that must
   stay private: the local login name and home directory, the global git name and email address
   and the address's domain, any path under `/Users` or `/home`, any email address, strings
   shaped like GitHub, OpenAI, Slack, AWS or Google credentials, JSON Web Tokens and private key
   blocks, and any `api_key`, `secret`, `token` or `password` assigned a long value. Each hit is
   printed as file and line number.
4. **Prints** `git status --short`, so the next step, reading the diff and committing, is in
   view.

It exits non-zero when a file needs a manual merge or the scan hit something, so a commit made
by reflex after it stops.

Run as `./sync.sh --install`, it copies every mirrored file from the checkout into `~/.claude`,
creating directories as needed. An existing file that differs is kept beside the new one as
`<file>.bak`. This is the first run on a new machine, and the way to try the files yourself.

## `sync-allow.txt`

Optional, and not present in this repository. When it exists next to `sync.sh`, each non-empty
line is a literal string, and a scan hit whose line contains one of them is ignored. It is for a
false positive that belongs in a published file, such as a documented example address. The file
itself is never scanned.

## Using it yourself

Clone the repository, or a fork of it, to `~/src/dotclaude` and install the mirrored files:

```bash
git clone https://github.com/lambdakilo/dotclaude.git ~/src/dotclaude && cd ~/src/dotclaude && ./sync.sh --install
```

Then restart Claude Code so the hook is picked up. The rules file names `~/src/dotclaude` as the
checkout, so change that section if you clone elsewhere. An existing `~/.claude/settings.json`
of yours is kept as `settings.json.bak`, so merge your own values back in by hand.

From then on, `./sync.sh` on its own is the whole routine: pull, reconcile, scan, read the diff,
commit, push.

## License

Prose, meaning `CLAUDE.md` and this README, is licensed under Creative Commons
Attribution-ShareAlike 4.0 International. See [`LICENSE-CC-BY-SA-4.0`](LICENSE-CC-BY-SA-4.0).

Everything else is licensed under the GNU Affero General Public License, version 3 or (at your
option) any later version. See [`LICENSE`](LICENSE).
