# Standing rules for every project

These apply in every session, whatever directory Claude Code was started from. Project memory is
keyed to the start directory, so rules that hold everywhere live here instead of in memory. This
file names no person, organisation, customer or repository, so anyone can copy it as is. Names that
apply to one repository belong in that repository's project memory.

## Git identity and attribution

- Never override the git author. Use the identity already configured in the repo or globally
  (check with `git config user.email`). Never pass `-c user.email=...` or guess an address.
- Never add `Co-Authored-By: Claude`, "Generated with Claude Code", or any Claude or Anthropic
  attribution to commits, PR bodies, or issues. The `attribution` setting also enforces this.

## Remote state

- Run `git fetch --all --prune` before relying on remote state: which branches exist, where the
  default branch is, whether a branch was merged, what an open PR is based on. Remote-tracking
  refs go stale between sessions, and a decision made on a stale ref is wrong in a way that is
  hard to notice afterwards.
- A `UserPromptSubmit` hook in `~/.claude/settings.json` runs `~/.claude/hooks/git-fetch-prune.sh`
  in the background on every prompt. Inside a repository with remotes it fetches all of them with
  pruning at most once every 15 minutes per repository, with every credential prompt disabled so
  it can never hang a prompt. It is a safety net, not a substitute for fetching before a decision.

## Commit messages

- Wrap every line of a commit message at 72 columns, the subject included. Neither GitHub nor
  `git log` reflows long lines, so they break the rendering.
- The message proper comes first: the subject, a blank line, then a body that says what changed
  and why. The prompts follow after another blank line, never before the body. PR bodies are the
  other way round, as described below.
- The prompt section opens with two lines. The first is
  `Prompts behind this commit, as given to Claude Code` and the second is
  `(model <id>, effort <level>):`, with the model id and effort level of the running session,
  taken from the session or from `model` and `modelSettings` in `~/.claude/settings.json`,
  never from memory. Then come the prompts behind the change: those given since the session's
  previous commit, every prompt of the session for its first commit, and for a follow-up to a
  commit made under the same prompt that prompt again. They keep their session numbers, each on
  its own line followed by the prompt as `>` quoted lines, verbatim, typos and lowercase
  included, wrapped onto further `>` lines at 72 columns. Mark answers to questions with a short
  parenthetical, and put AskUserQuestion selections as nested `>` lines under the prompt. When
  those prompts use abbreviations, an `Abbreviations:` section follows with one line per
  abbreviation and its expansion. When they use none, there is no such section.
- Text the user pasted into a prompt (a pasted block: a log, code, a file, an address, a message
  from someone else) is never quoted, in a commit message or in a PR body. Replace it where it
  stood with a bracketed description of what it was, such as `[pasted: an email address]` or
  `[pasted: 40 lines of test output]`.
- The PR rules on exclusion and redaction apply to commit messages too: leave out meta prompts,
  and in public and upstream repositories redact downstream project, client and customer names
  with square brackets. The one exception is the public configuration repository, where prompts
  about this file or about Claude Code settings are the prompts behind the change and stay in.
- Re-read this file from disk before writing a commit message or a PR body. A session loads it
  once at start, so an edit made from another session while this one runs stays invisible until
  the file is read again.

## Pull requests

- Open PRs as drafts.
- Claude's part of the body is the two collapsed blocks below, then the repository's pull
  request template filled in as described further down. Nothing else: no free-form summary or
  test plan outside the template. Without a template the body ends after the blocks and the
  user writes the description.
- The PR body starts with two collapsed `<details>` blocks, directly under the title and above
  everything else. They are a TL;DR for the reviewer.
- First block: `<details><summary>~/.claude/CLAUDE.md</summary>`. Inside it, put the full contents
  of this file verbatim in a fenced ```` ```markdown ```` code block, so teammates can copy it as
  is. It comes first because it is what gets read first. Refresh it
  whenever this file changes. Keep it free of personal names, emails, organisation and customer
  names and absolute home paths, as this file itself is.
- Second block: `<details><summary>Prompts behind this PR</summary>`. Its first line names the
  model and effort level the session ran with, for example `Model: claude-fable-5-1, effort:
  medium`. Take them from the running session, or from `model` and `modelSettings` in
  `~/.claude/settings.json`, never from memory. Then number every prompt from the session in
  order and quote each verbatim, typos and lowercase included, as a `>` blockquote (`**1.**` on
  its own line, then the `>` quote). Include prompts that produced no commit. Mark answers to
  questions with a short parenthetical, and put AskUserQuestion selections as nested `>` lines
  under the prompt.
- Directly under the model line, before the first prompt, a nested
  `<details><summary>Abbreviations</summary>` block lists every abbreviation used anywhere in the
  quoted prompts with its expansion, one per line, so a reader who does not know one can open
  the list and check. When the prompts use none, leave the block out.
- Pasted text inside a quoted prompt is replaced by a bracketed description, as the commit
  message rules say. The prompts may come before the rest of the body here, unlike in a commit.
- Leave out meta prompts: anything about Claude Code itself, its memory, this rules file, or how
  to format the PR, even when the same prompt also asks for a small fix to the PR. Only prompts
  about the change under review belong in the PR.
- Below the blocks, fill in the repository's pull request template when it has one. Look in
  `.github/` for `pull_request_template.md` or `PULL_REQUEST_TEMPLATE.md`, a
  `PULL_REQUEST_TEMPLATE/` directory, and the same names at the repository root and under
  `docs/`. Keep the template's headings, comments and order, and answer each section briefly:
  one sentence on what has changed, the issue links (`Closes #n`) and any related documents,
  and the manual steps a reviewer follows to verify the change in the running app. A section
  that asks a yes/no question with a checkbox for each answer, such as "Added tests?" or "Is
  documentation up-to-date?", gets only the box that applies ticked: nothing more when the
  answer is yes, one sentence saying why when it is no. `gh pr create` applies the template
  only when it composes the body interactively. `--body` and `--body-file` replace it
  silently, so the body file has to contain the template text.
- Add a prompt about the change under review to the PR's prompts block in the same turn it is
  answered, whether or not anything is committed, and refresh both blocks again after every
  commit and push. Read the live body with `gh pr view <n> --json body --jq .body`, edit it as
  a file, write it back with `gh pr edit <n> --body-file`, and re-read to confirm. Below the
  blocks, change only a template answer that a later commit made wrong, and keep every edit
  the user has made there.
- Public and upstream repositories: never name a downstream project, its client or its
  customer. Say "a downstream project". Redact them in quoted prompts with square brackets, and
  redact absolute paths and container names that carry them.
- Remote layout decides the flow. If the repo has an `upstream` remote, it is a fork checkout:
  `origin` is the user's fork and `upstream` is the canonical repo. If there is only `origin`,
  the user has write access and works on it directly.
- Fork checkouts: the user has read access on the upstream repo. Resolve the GitHub handle at
  runtime with `gh api user --jq .login` (never hardcode it). Branch from `upstream/<default
  branch>`, push to `origin`, and open the PR against the upstream repo with
  `--repo <upstream-owner>/<repo> --head <handle>:<branch> --base <default branch>`. Switch the
  checkout back to the branch it was on afterwards.
- Direct checkouts: branch from `origin/<default branch>`, push to `origin`, and open the PR
  with `--head <branch>` against that default branch.
- Upstream PRs only when asked. First check what is already open with
  `gh pr list --repo <upstream-owner>/<repo> --author @me` and prefer adding to an open PR.
- In a direct checkout, one draft PR at a time. Push follow-ups to it, do not open a second.

## Prose

- No em dashes, no en dashes used as dashes, no semicolons as connectors. Use a full stop, a
  comma, or a colon. Applies to chat, commits, PR bodies, comments, and docs.
- Name an organisation by its full registered name every time. Never "we", "ours", "they" or
  "theirs" standing in for a company. The names that apply to a repository live in its project
  memory.

## Prompt feedback

- End every reply with a short section headed `Prompt feedback` that says how the prompt behind
  it could have been better: what was missing, what was ambiguous, what was unnecessary, and a
  rewritten prompt when the change is more than a word. Keep it to a few lines. When the prompt
  was already as good as it could be, say so in one line rather than inventing a flaw.

## Comments

- Match the comment density of the file being edited and the files beside it. Look before writing
  one. Landing a file at many times the local density is a review finding, not thoroughness.
- Comment only what the code cannot say: an external constraint, a bug being worked around, an
  invariant that is not visible from the lines themselves. Never restate what the next line does.
- Do not argue a decision in the source. Reasoning written to persuade a reviewer belongs in the
  commit message or the PR body, which is where they look for it. Moving it there is not losing it.
- Prefer a clearer name or a smaller function over a comment explaining the unclear version.

## Running things

- Run the repo's verify command (lint, typecheck, unit tests) after meaningful edits, not only at
  commit time.
- Starting a local stack to debug is fine. Nothing may still be running when the turn ends.
- Never run environment or deployment tooling against a remote environment. Confirm before
  destructive commands.
- Prefer official features over custom glue that wraps unstable internals. If only custom works,
  say so and name the drift risk before building it.
- Probe before spending quota on rate-limited APIs. Read retry-after, no blind retry loops.

## Public configuration repository

- The parts of `~/.claude` that help other people learn this workflow are mirrored in a public
  git repository. Its checkout lives at `~/src/dotclaude`. Mirrored today: this file,
  `settings.json` and `hooks/`. The checkout also holds its own `README.md`, licence texts and
  `sync.sh`.
- The mirrored copy keeps the name `CLAUDE.md`. A session started inside the checkout would load
  it as project memory on top of the global file, so `settings.json` lists
  `**/dotclaude/CLAUDE.md` in `claudeMdExcludes`. Claude Code reads no other mirrored file from
  a repository root, so nothing else needs a different name.
- `sync.sh` pulls the checkout fast-forward, then reconciles each mirrored file: one the pull
  changed is installed into `~/.claude`, one changed locally is copied into the checkout, and one
  changed on both sides stops the run for a manual merge. It then scans everything that would be
  published for the local user name, home paths, the git identity, email addresses and
  credential-shaped strings, exits non-zero on a hit, and prints `git status`. Literals listed
  one per line in `sync-allow.txt`, when that file exists, are exempt.
- Whenever a session changes a mirrored file, run `sync.sh`, read the diff, commit and push to
  the default branch in the same turn. No PR: the checkout has one owner. When a new file under
  `~/.claude` would help other people (a hook, a skill, a command, an agent), add it to the list
  in `sync.sh` first.
- New machine: clone the repository to `~/src/dotclaude`, run `./sync.sh --install` to copy the
  mirrored files into `~/.claude` (existing files that differ are kept as `.bak`), and set the
  repository-local git identity to match the existing history, from
  `git log -1 --format='%an <%ae>'`, before the first commit. Restart Claude Code so the hook
  loads.
- Commits there carry the repository-local identity the user set in the checkout: the public
  account handle and a disposable address, so no personal name lands in the history. That is the
  configured identity for that repository, and the rule above about never overriding the author
  applies to it as it stands.
- That repository never contains a personal name, an employer, client or customer name, a
  project name, a secret, or anything else that discloses what the user works on. No email
  address either: the disposable address lives in the checkout's git config and nowhere else.
  Redact quoted prompts with square brackets where needed, as for upstream PRs.

## Memory hygiene

- Memory is per start directory. When a rule should hold everywhere, put it in this file, not in
  memory. When starting in a parent folder like `~/src`, also read the memory of the project you
  end up working in under `~/.claude/projects/-Users-<user>-src-<project>/memory/MEMORY.md`.
