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
- When squashing a pull request, by squash merge or by squashing its commits into one before
  merging, add a `Co-authored-by: <name> <address>` trailer to the squashed commit for every human
  account whose commits are being squashed, apart from the author the squashed commit already
  carries. Take each name and address from `git log --format='%an <%ae>'` over the squashed range,
  never from memory. GitHub drafts these trailers in its squash-merge dialog: keep them. The rule
  above still holds, so no trailer ever names Claude or Anthropic.
- When squashing a pull request, also add a `Reviewed-by: <name> <address>` trailer for every
  human account that submitted a review on it. Take the identity from that account's own commits
  in the same repository: `gh api 'repos/<owner>/<repo>/commits?author=<login>&per_page=1'`
  gives the name and address it commits under. Fall back to the account's
  `<id>+<login>@users.noreply.github.com` address, with the id from `gh api users/<login>`, and
  skip the account when neither resolves. A review alone never earns a `Co-authored-by`, an
  address never comes from another repository, and a bot never gets a trailer.

## Remote state

- Run `git fetch --all --prune` before relying on remote state: which branches exist, where the
  default branch is, whether a branch was merged, what an open PR is based on. Remote-tracking
  refs go stale between sessions, and a decision made on a stale ref is wrong in a way that is
  hard to notice afterwards.
- A `UserPromptSubmit` hook in `~/.claude/settings.json` runs `~/.claude/hooks/git-fetch-prune.sh`
  in the background on every prompt. Inside a repository with remotes it fetches all of them with
  pruning at most once every 15 minutes per repository, with every credential prompt disabled so
  it can never hang a prompt. It is a safety net, not a substitute for fetching before a decision.
- A `SessionStart` hook runs `~/.claude/hooks/git-prune-gone-branches.sh` when a session starts,
  resumes, is cleared or is forked. Inside a repository with remotes it runs the fetch above, then
  deletes every local branch whose upstream branch is gone, as long as nothing on it would be
  lost: every commit is already on the base remote's default branch, or the branch tip is the
  head of a pull request GitHub still holds. Every other gone branch stays, and the hook names it
  in the session's context: mention those once in the first reply and delete only the ones the
  user names. Deleted names and hashes go to `claude-code-deleted-branches.log` in the git
  directory, and `git branch <name> <hash>` brings one back.

## Git commands

- Use `git switch` to change branches and `git switch -c` to create one, in commands run and in
  commands given to the user, whenever it can do the job. `git checkout` also restores files
  from the index or another commit, so a typo or a stray path in a checkout can overwrite work
  where a switch would refuse. Reach for `checkout` only for what `switch` and `restore`
  cannot do, such as checking out a pathspec from a commit into the work tree.
- After every branch switch in a repository with submodules, run `git submodule update --init`.
  The switch moves each submodule's pin in the index but leaves its work tree where it was, so a
  stack that bind-mounts the submodule keeps running the old code, and a cache built by the
  previous pin can fail in ways nothing logs. Run the update every time, without checking first
  whether the pin moved. `gh pr checkout` is a switch too and leaves submodules alone unless
  given `--recurse-submodules`. This holds for switches run and for switch commands given to the
  user. Added 2026-10-07 after a review's test steps gave a branch switch without it, and made
  unconditional the same day.

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
- Claude's part of the body is the two blocks below, then the repository's pull request
  template filled in as described further down. Nothing else: no free-form summary or test
  plan outside the template. Without a template the body ends after the blocks and the user
  writes the description.
- The two blocks come directly under the title and above everything else. They are a TL;DR
  for the reviewer.
- First block: a fenced code block holding the URL of the public configuration repository
  described under Public configuration repository below, so teammates can read and copy the
  rules at their source. Take the URL at runtime from the checkout's `origin` remote, with
  `git -C ~/src/dotclaude remote get-url origin`, rewritten from the SSH form to https and
  without the `.git` suffix, never from memory. A code block and not a Markdown link: a link's
  visible text can differ from where it goes, while a URL the reader pastes is one they see in
  the address bar before they go. Nothing in Markdown keeps invisible or look-alike characters
  out of a code block, so the safeguards are the reader's look at the pasted URL and the
  description's edit history, which names every account that changed it. This block replaced
  a verbatim copy of this file on 2026-09-30, which went stale with every edit.
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
- Test steps for a change under review, in a PR body's "How to verify" or given in chat, end
  with the last check. No step switches the checkout back to the branch it was on before: the
  next review's checkout replaces the branch anyway, and where to go next is the reader's call.
  Automated checks come first, the verify command and then end to end, and the manual pass comes
  last, unless the user says otherwise: a failing spec shows before the slow part, and end to end
  never follows the manual steps. Added 2026-10-07 after review steps closed with a switch back to
  the previous branch and put the specs after the manual pass.
- Manual steps follow the screen. Before writing one, open the component or the running page and
  take the order of fields and clicks from it, so a dialog that shows type, then name, then
  company is filled in that order and never in the order the step's purpose brings them to mind.
  Every control is named by the label the reader sees, in bold, in the locale the app renders
  (the catalog's `msgstr`, or the `msgid` when that is empty), never by what it does for the
  flow: click **Lisää sisältö**, search for C and click its card, not "pick a content"; the
  row's **Poista**, not "remove it". A verb alone never stands for a control. When a label is on
  more than one control, say which: the row's, the dialog's, the bottom bar's. One action per
  sentence, followed by what the reader should now see, and two actions that each trigger the
  same thing get a sentence each, never "both ask too". Test data the reader creates gets the
  shortest name that works, a, b, c or 1, 2, 3, never a prefix like pr109. A step that searches
  by name says what to type and uses the shortest string the seed data does not contain, checked
  with a search in the grid first. Every action the reader takes is written down, also the ones
  that feel obvious: copy the address before pasting it, open the new tab before pasting into
  it, log in again after logging out. A step never relies on something the reader has not been
  told to do. Added 2026-10-10 after the PR 109 steps put Yritys before Nimi, wrote "pick" for a
  three-click flow and joined two checks into one sentence, so the reader made no change, saw no
  dialog and looked for a Takaisin that was not there. The same day the steps named the test
  data pr109 a, b and c, and pasted an address the reader had never been told to copy.
- Add a prompt about the change under review to the PR's prompts block in the same turn it is
  answered, whether or not anything is committed, and refresh the prompts block again after
  every commit and push. Read the live body with `gh pr view <n> --json body --jq .body`, edit it as
  a file, write it back with `gh pr edit <n> --body-file`, and re-read to confirm. Below the
  blocks, change only a template answer that a later commit made wrong, and keep every edit
  the user has made there.
- The prompt that says to merge is a prompt about the change too. Add it to the PR's prompts
  block before merging, and to the prompts section of the squash commit, which is the commit
  that prompt creates. Added 2026-10-08 after a merge prompt was left out of a PR body.
- When a PR, draft or not, closes an issue, assign the user to that issue, with
  `gh issue edit <n> --add-assignee <handle>` and the handle from `gh api user --jq .login`.
  Do it when the PR is opened and again whenever its `Closes` list changes, and skip the
  issue silently when the edit is refused for lack of permission. The board then shows who
  holds the work without a separate step. Added 2026-10-08.
- Screenshots and recordings go into the PR body when the change is visual, anything that
  alters what a page renders, and the repository's pull request template carries the
  `[!IMPORTANT]` alert asking for a recording or screenshots. Capture them from the local
  stack on fixture data with a scratch Playwright script in the scratchpad, on the
  repository's Playwright install, never a config change in the repository: one PNG per
  manual step of "How to verify", in the state that step describes, named after the step,
  and a WebM only where motion is the point. Upload the set through GitHub's own editor in
  Claude in Chrome, where the user is signed in, with the user's go for the set: drop the
  files into the PR's comment box, copy the markdown GitHub puts there, and clear the box
  without posting. Put that markdown under the alert in a
  `<details><summary>Screenshots</summary>` block, a blank line after the summary so the
  images render, one line per file naming the step it shows, and write the body back with
  `gh pr edit`. Redo the set after every push that changes what is on screen, the way the
  prompts block is refreshed, so no reviewer judges a stale picture. Added 2026-10-09.
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
- In a direct checkout, one draft PR per feature. Follow-ups to the work under review, including
  tooling or docs it needs, go to that PR's branch. A different feature gets its own branch and
  draft, even while other drafts are open.

## Prose

- No em dashes, no en dashes used as dashes. Use a full stop, a comma, a colon or a semicolon.
  Applies to chat, commits, PR bodies, comments, and docs. Semicolons were banned too until
  2026-10-03.
- Plain keyboard characters only, in every text a session writes: straight quotes and
  apostrophes, `>` or the word "then" between the clicks of a path or the items of a breadcrumb,
  three dots for an ellipsis. No typographic quotes or apostrophes, no angle quotation marks
  such as the chevron between breadcrumbs, no guillemets, no arrow or ellipsis characters. A
  character outside ASCII belongs only inside a word that needs it, such as ä or ö, or inside a
  label quoted from the screen. Added 2026-10-10 after breadcrumbs were written with a chevron
  character between them, which the reader could neither read nor type.
- Name an organisation by its full registered name every time. Never "we", "ours", "they" or
  "theirs" standing in for a company. The names that apply to a repository live in its project
  memory.
- A command the reader is meant to run goes in a fenced code block tagged with its shell, never
  inline in a sentence. A fenced block reads as a command and copies as one, an inline span
  hides in the prose and breaks at the first backtick. One command per block. Several commands
  share a block only joined with `&&`, when they form one sequence in which each step needs the
  one before it to have succeeded, so a paste stops at the first failure. Independent commands,
  and alternatives, get a block each. Decide which of the two it is every time, never list
  unjoined commands on separate lines of one block. This holds for every Markdown a session
  writes: PR bodies, docs, memory files and chat. A command that a sentence describes rather
  than asks the reader to run, such as the note on `gh pr create` under Pull requests above,
  stays inline.
- A step in a list is no exception, and the "How to verify" steps of a PR body are where this
  slips: the fenced block goes under the step, indented to it, not inline in the step's
  sentence. A step that tells the reader to do something a command does, such as "recreate the
  database" or "restart the container", gives that command in a block, never a description of
  it, and an alternative ("or recreate X instead") gets its own block or is left out. The
  reader of a verify step is at a terminal and pastes, so a step without its block sends them
  to look the command up. Slipped on 2026-09-29: one verify step held a start command inline
  and named a recreate that takes three commands without giving any.
- Answer first, then only what changes what the reader does next, then stop. No recap, no
  "check by hand" section, and no numbered steps unless they are commands run in order. When
  asked for a list, give the list and nothing around it. Added 2026-10-07 after a pass over a
  month of transcripts found eight complaints about length and none about level.
- Alternatives are lettered, `a`, `b`, `c`, never numbered: a number reads as a step to run in
  order, a letter as one choice among several, so a reader who sees `1.` and `2.` starts on
  both. Numbers stay for commands run in order. Added 2026-10-09 after two ways to finish a
  task were offered as 1 and 2.

## Prompt feedback

- End every reply with a short section headed `Prompt feedback` that says how the prompt behind
  it could have been better: what was missing, what was ambiguous, what was unnecessary, and a
  rewritten prompt when the change is more than a word. Keep it to a few lines. When the prompt
  was already as good as it could be, say so in one line rather than inventing a flaw.
- Write the rewritten prompt itself as the user would type it: all lowercase, names included,
  and without characters that need the shift key when a plain one does the job, so commas and
  full stops in place of colons, quotes, question marks and parentheses. Make it as short as it
  can be while still being a good prompt, and never longer than a few lines. The rest of the
  section keeps normal capitals and punctuation, so `Rewritten: "pull pr 94 and redo the
  review"` is right and `Rewritten: "Pull PR 94, redo the review!"` is not.

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
- A `cd` is paired with its `cd` back at the end of the same command,
  `cd playwright && npx playwright test; cd ..`, with the return joined by `;` so it runs
  whether or not the step succeeded. A subshell does not count: the reader sees no return in
  it. A tool's own directory flag, such as `git -C` or `npm --prefix`, avoids the question.
  This holds in commands run and in commands given to the user. The working directory persists
  from one command to the next, and a later command written for the project root then runs in
  the wrong place. Slipped on 2026-10-06 with a bare `cd playwright && npx playwright test`,
  and on 2026-10-07 with the same inside a subshell.
- Never run environment or deployment tooling against a remote environment. Confirm before
  destructive commands.
- Prefer official features over custom glue that wraps unstable internals. If only custom works,
  say so and name the drift risk before building it.
- Probe before spending quota on rate-limited APIs. Read retry-after, no blind retry loops.

## Permissions

- Auto mode blocks a session from editing its own permissions, so when the auto mode
  classifier refuses an action that an allow rule in `~/.claude/settings.json` would let
  through, finish everything that does not depend on it, then give the user the script that
  adds the rule, in a fenced `bash` block in the same reply, and stop. The script is a
  `python3 - <<'EOF'` heredoc that loads the file, appends each missing rule to
  `permissions.allow`, and writes it back with
  `json.dumps(d, indent=2, ensure_ascii=False) + '\n'`, which round-trips the file byte for
  byte so the diff is the rules alone. One script names every rule the turn needs:
  `Bash(<prefix>:*)` with the prefix the refused command started with, such as
  `Bash(gh pr reopen:*)`, or `Edit(<path>)` for a refused file edit, such as
  `Edit(~/.claude/CLAUDE.md)`. The reply says in a line what each rule unlocks. The user
  runs the script; after that the mirrored `settings.json` has changed, so run `sync.sh`,
  commit and push as under Public configuration repository. Added 2026-10-08 after a
  session in which four refusals each cost a round trip.
- A rule matches the literal start of the command, so once it exists the session runs the
  allowed command bare: not behind `cd ... &&`, not in a pipe, and with `~` unexpanded where
  the rule has it. Paths in rules use `~`, never the home directory spelled out, which the
  mirror's scan rejects. No rule gets past the classifier's self-modification and instruction
  poisoning refusals: on 2026-10-08 an `Edit` rule for this file did not take, so an edit of
  this file and a commit in the mirror both went to the user as a script, the edit as a
  `python3` heredoc that inserts the text at a named anchor.

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
