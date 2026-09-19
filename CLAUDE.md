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

## Pull requests

- Open PRs as drafts.
- Never write the pull request description. The user writes it themselves. Claude's part of the
  body is the two collapsed blocks below and nothing else: no summary, no test plan, no
  filled-in template sections.
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
  the list and check. The block is always present. When the prompts use none, its only line is
  `None.`
- Leave out meta prompts: anything about Claude Code itself, its memory, this rules file, or how
  to format the PR, even when the same prompt also asks for a small fix to the PR. Only prompts
  about the change under review belong in the PR.
- Below the blocks, paste the repository's pull request template verbatim and unfilled when it
  has one, so the user has it in place to fill in. Look in `.github/` for
  `pull_request_template.md` or `PULL_REQUEST_TEMPLATE.md`, a `PULL_REQUEST_TEMPLATE/` directory,
  and the same names at the repository root and under `docs/`. `gh pr create` applies the
  template only when it composes the body interactively. `--body` and `--body-file` replace it
  silently, so the body file has to contain the template text. Without a template the body ends
  after the blocks.
- Update the blocks after every commit and push, and also at the end of every session that
  added a prompt about the change under review, even when the session made no commit. Read
  the live body with `gh pr view <n> --json body --jq .body`, edit it as a file, write it back
  with `gh pr edit <n> --body-file`, and re-read to confirm. Change nothing below the blocks.
  That part of the body belongs to the user.
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
  `sync.sh`, which copies the mirrored files in from `~/.claude` and exits non-zero when it finds
  the local user name, a home path, the git identity, an email address, or anything that looks
  like a credential.
- Whenever a session changes a mirrored file, run `sync.sh`, read the diff, commit and push to
  the default branch in the same turn. No PR: the checkout has one owner. When a new file under
  `~/.claude` would help other people (a hook, a skill, a command, an agent), add it to the list
  in `sync.sh` first.
- That repository never contains a personal name, an email address, an employer, client or
  customer name, a project name, a secret, or anything else that discloses what the user works
  on. Redact quoted prompts with square brackets where needed, as for upstream PRs.
- Commit messages there quote the prompts behind the change: the subject line, a blank line, then
  every prompt of the session in order, each as a number on its own line followed by the prompt
  as `>` quoted lines, verbatim, typos and lowercase included. An `Abbreviations:` section with
  one line per abbreviation and its expansion follows when the prompts use any. The meta-prompt
  exclusion for PRs does not apply: prompts about this file or about Claude Code settings are
  the prompts behind the change.

## Memory hygiene

- Memory is per start directory. When a rule should hold everywhere, put it in this file, not in
  memory. When starting in a parent folder like `~/src`, also read the memory of the project you
  end up working in under `~/.claude/projects/-Users-<user>-src-<project>/memory/MEMORY.md`.
