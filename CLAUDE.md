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
  There, and in every directory `sync.sh` mirrors into, internal or not, a quoted prompt keeps
  only the part about the rules or the settings; the rest becomes a bracketed note such as
  `[an ask about a downstream project left out]`, and what stays is redacted as for upstream
  PRs, a content type's name in the project's language included, since it names the project
  as surely as the project's name does. Added 2026-10-12 after a mirror commit quoted a whole
  prompt that named a customer's content type and their backend vendor.
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
  documentation up-to-date?", keeps only the box that applies, ticked, and the other box's
  line is deleted rather than left empty: nothing more when the answer is yes, one sentence
  saying why when it is no. Changed 2026-10-13 from ticking one and leaving the other.
  `gh pr create` applies the template only when it composes the body interactively. `--body` and `--body-file` replace it
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
  flow: click **Add item**, search for C and click its card, not "pick an item"; the row's
  **Delete**, not "remove it". A verb alone never stands for a control. When a label is on more
  than one control, say which: the row's, the dialog's, the bottom bar's. One action per
  sentence, followed by what the reader should now see, and two actions that each trigger the
  same thing get a sentence each, never "both ask too". Test data the reader creates gets the
  shortest name that works, a, b, c or 1, 2, 3, never a prefix such as the PR's number. A step
  that searches by name says what to type and uses the shortest string the seed data does not
  contain, checked with a search in the grid first. Every action the reader takes is written
  down, also the ones that feel obvious: copy the address before pasting it, open the new tab
  before pasting into it, log in again after logging out. A step never relies on something the
  reader has not been told to do. A step that opens a page gives its full local address, such
  as `http://localhost:3000/items`, never the page's name alone, so the reader pastes instead of
  hunting through the navigation. Added 2026-10-10 after review steps put a dialog's fields out
  of order, wrote "pick" for a three-click flow and joined two checks into one sentence, so the
  reader made no change, saw no dialog and looked for a back button that was not there. The
  same day the steps prefixed the test data with the PR's number, and pasted an address the
  reader had never been told to copy. The address rule came on 2026-10-13, after a step named a
  page with no URL.
- A PR review runs the PR's own "How to verify" steps and hands back corrections to them, never a
  test script of the reviewer's own, however complete. The reply gives the commands first, each
  in its fenced block: the branch switch with the submodule update, whatever starts the stack,
  the verify command and the end to end run. Then only what the author's steps need: a label
  that is not on screen, a click left out, a step the seed data cannot do, a change the steps do
  not cover, a check that failed. When the steps are right as they stand, say so in a line.
  The reply is one numbered list the reader follows from a cold start: the branch switch with
  the submodule update, whatever starts the stack, the cache clear, the verify command and the
  end to end run come first, each as its own step with its command in a fenced block under it,
  then the manual steps in the standing form, taken from the screen and no wider than the PR's
  own steps plus the changes those steps skip. A manual step that runs a command carries that
  command in a block under it, never a description of it. Where the PR's step has a screenshot
  or video, the matching step names it at its start, "the PR's screenshot under step 3 shows
  this dialog", and the comparison comes before the click that closes what the picture shows;
  a PR that puts the picture after the OK or the save gets a line for it under what the
  instructions missed. The list ends with what the PR's instructions missed: state the
  reviewer builds by hand through a workflow the specs already cover, which the PR should have
  seeded; a change without a step; a claim the run disproved; a picture placed after the step
  it shows. That section ends with the command steps of the list, from the switch to the end
  to end run, as GitHub markdown inside a four-backtick fence, numbered as in the reply, so
  the PR's "How to verify" can take them over unchanged. That block is the one thing in the
  reply written to be pasted into the PR. Added 2026-10-12 after a review answered six author
  steps with twenty-eight of its own, then handed back a paste-ready section, then steps
  without their commands, the same day; the picture and markdown rules came that evening.
- Never post a comment, a review thread reply, a review or an issue comment on GitHub: every
  word posted goes out under the user's name, and the user writes those. A review finding is
  answered by the commit that fixes it, and the reply to the user lists, per thread, what
  changed and in which commit, so the user can answer and resolve the threads themselves.
  Editing a PR body or an issue the user owns, assigning, reopening and closing stay allowed,
  as above. Added 2026-10-13 after a session answered and resolved five review threads as the
  user.
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
  and a WebM only where motion is the point. A recording is made with `slowMo` of about 400 ms
  on the browser launch and a pause of two or three seconds at every state a step describes,
  since a Playwright run at full speed is too fast to follow. Whenever screenshots or
  recordings exist for a PR and show what it changes, upload them to it in the same turn they
  are made, without asking first: a reply never ends with a set waiting for a go. Upload them
  through GitHub's own editor, where the user is signed in: drop the files into the PR's
  comment box, copy the markdown GitHub puts there, and clear the box without posting. Use
  Claude in Chrome when it is connected, and otherwise the app's built-in browser pane, which
  has no file upload tool: push the files to the PR's repository on a throwaway branch built
  with git plumbing (`hash-object`, `update-index` on a temporary index, `write-tree`,
  `commit-tree`, `update-ref`, `push --no-verify`), then in the page fetch each from
  `https://github.com/<owner>/<repo>/raw/<branch>/<file>` with `credentials: 'same-origin'`,
  put the blobs in a `DataTransfer`, assign it to the comment box's `input[type=file]`,
  dispatch a bubbling `change`, read the markdown from the textarea after a few seconds, and
  delete the branch afterwards. A Chrome that does not connect is never a reason to stop. The
  go per set was dropped on 2026-10-14 after a session captured a set and stopped to ask, and
  the pane method was added the same day after the next turn stalled on a Chrome that was not
  connected. Each picture goes at the start of the step it shows, never on the line
  with the number: that line holds the number and one short clause naming what the picture
  shows, the picture follows on its own line under it, indented to the step, and the step's
  text comes after the picture, so the reader sees what to look for before acting. A
  recording goes the same way under the first step it covers, as a bare attachment URL on its
  own line, which GitHub renders as a player where a `[name](url)` link does not. Write the
  body back with `gh pr edit`. Redo the set after every push that changes what is on screen,
  the way the prompts block is refreshed, so no reviewer judges a stale picture. Added
  2026-10-09; the pictures moved from a details block under the alert to the start of their
  steps on 2026-10-13, since a reader wants to know what a step looks like before doing it,
  and off the number's line the same day.
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
- One draft PR per session. Everything a session is asked to change goes to the branch of the
  PR in play, follow-ups to the work under review and unrelated small changes alike, and a
  second PR is opened only when the user says so in that session. Until 2026-10-13 a different
  feature got its own branch and draft, and a one-paragraph docs change went out as a second
  draft beside the feature PR the session was on; the user closed it and had the change moved.

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
- Starting a local stack to debug is fine. Nothing may still be running when the turn ends:
  stop the project's container stack with the project's own stop command before the reply,
  every turn, even when the next turn will start it again, and say in the reply that it is
  stopped. A project memory that says to keep a stack up does not override this. Made explicit
  2026-10-13 after a turn ended with a stack up on a project memory from 2026-10-08 that said to
  keep it up.
- A command that must run in another directory uses the tool's own directory flag, such as
  `git -C` or `npm --prefix`, and otherwise a subshell, `(cd playwright && npx playwright test)`,
  which returns on its own. Never `cd playwright && npx playwright test; cd ..`: when the `cd`
  fails, the return still runs and leaves the reader one level above the project. This holds
  in commands run and in commands given to the user, since the working directory persists from
  one command to the next. The subshell replaced the paired return on 2026-10-12, after a PR's
  own steps showed it; the paired return had stood since 2026-10-06.
- Never run environment or deployment tooling against a remote environment. Confirm before
  destructive commands.
- Prefer official features over custom glue that wraps unstable internals. If only custom works,
  say so and name the drift risk before building it.
- Probe before spending quota on rate-limited APIs. Read retry-after, no blind retry loops.

## Permissions

- Auto mode blocks a session from editing its own permissions, so when the auto mode
  classifier refuses an action that an allow rule in `~/.claude/settings.json` would let
  through, finish everything that does not depend on it, then give the user the script that
  adds the rule, in a fenced `bash` block in the same reply, and stop. The script is shell:
  `jq` appends each missing rule to `permissions.allow` and writes the file back with its
  default two-space indent, which round-trips the file byte for byte (checked 2026-10-12), so
  the diff is the rules alone. One script names every rule the turn needs:
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
  this file and a commit in the mirror both went to the user as a script, the edit as a `sed`
  insert at a named anchor.
- Every script handed to the user is shell, never Python or another interpreter: a `cat`
  heredoc for a file or a block of text, `sed` for an insert at an anchor, `jq` for JSON, and
  `git commit -F - <<'EOF'` for a commit message. Added 2026-10-12 after a rules edit went
  out as a python3 heredoc.

## Public configuration repository

- The parts of `~/.claude` that help other people learn this workflow are mirrored in a public
  git repository. Its checkout lives at `~/src/dotclaude`. Mirrored today: this file,
  `settings.json`, `hooks/` and `workflows/`. The checkout also holds its own `README.md`,
  licence texts and `sync.sh`.
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
  Literals listed one per line in the git-ignored `sync-deny.txt` fail the scan in any case,
  and `sync.sh --check-message`, run from the untracked commit-msg hook of the checkout and of
  each mirror, holds commit messages to the same list.
- Whenever a session changes a mirrored file, run `sync.sh`, read the diff, commit and push to
  the default branch in the same turn. No PR: the checkout has one owner. When a new file under
  `~/.claude` would help other people (a hook, a skill, a command, an agent), add it to the list
  in `sync.sh` first.
- `sync.sh` also copies every published file into each directory listed in `sync-mirrors.txt`, an
  optional file beside it that git ignores, and prints each directory it copied into. When it
  reports one, commit and push in that repository too, in the same turn. Which directories those
  are and what each is for lives in the dotclaude checkout's project memory, never in this file
  or in a tracked file, so the public repository shows the mechanism and nothing it points at.
  Added 2026-10-10.
- New machine: clone the repository to `~/src/dotclaude`, run `./sync.sh --install` to copy the
  mirrored files into `~/.claude` (existing files that differ are kept as `.bak`), and set the
  repository-local git identity to match the existing history, from
  `git log -1 --format='%an <%ae>'`, before the first commit. Restart Claude Code so the hook
  loads.
- Commits there carry the identity configured in the checkout, and the rule above about never
  overriding the author applies to it as it stands: the user's own name with a disposable
  address. Changed 2026-10-10 from the public account handle, which the history never carried.
- That repository never contains another person's name, an employer, client or customer name,
  a project name, a secret, or anything else that discloses what the user works on. The user's
  own name may stand in the history, as the author or in a quoted prompt, but in no published
  file, which the scan enforces. No email address either: the disposable address lives in the
  checkout's git config and nowhere else. Redact quoted prompts with square brackets where
  needed, as for upstream PRs, and quote only the part of a prompt that is about the
  configuration, as the Commit messages section says; the mirrors follow the same rule.
  An example in a published file is a generic English placeholder, never a label, address,
  number or tool name from the session's project or employer, and a term that slips through
  goes into `sync-deny.txt`. Added 2026-10-15 after the manual-steps examples, two allow rules
  and four commit messages published a downstream project's labels, its local address and the
  employer's command line tool.

## Memory hygiene

- Memory is per start directory. When a rule should hold everywhere, put it in this file, not in
  memory. When starting in a parent folder like `~/src`, also read the memory of the project you
  end up working in under `~/.claude/projects/-Users-<user>-src-<project>/memory/MEMORY.md`.
