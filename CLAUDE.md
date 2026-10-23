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
  A `PreToolUse` hook, `~/.claude/hooks/git-fetch-before-remote-base.sh`, is that fetch for a
  command that branches, rebases, merges, hard-resets or adds a worktree from an `origin/` or
  `upstream/` ref: it runs the same script and waits, unless a fetch ran in the last 2 minutes.
- A `SessionStart` hook runs `~/.claude/hooks/git-prune-gone-branches.sh` when a session starts,
  resumes, is cleared or is forked. Inside a repository with remotes it runs the fetch above, then
  deletes every local branch whose upstream branch is gone, as long as nothing on it would be
  lost: every commit, or a patch-equivalent one, is already on the base remote's default branch
  or in a pull request GitHub still holds. Every other gone branch stays. The hook shows the user
  what it deleted and, whenever it changes, the set it kept, so a reply never repeats that list.
  Delete only the ones the user names. Deleted names and hashes go to
  `claude-code-deleted-branches.log` in the git directory, and `git branch <name> <hash>` brings
  one back.

## Git commands

- Use `git switch` to change branches, `git switch -c` to create one and `git restore` to put back
  files, from a commit with `--source <commit> --staged --worktree`, in commands run and in
  commands given to the user. `git checkout` does both jobs and picks one by what its argument
  names, so a typo or a stray path can overwrite work where a switch would refuse. Nothing needs
  it, and a `PreToolUse` hook, `~/.claude/hooks/no-git-checkout.sh`, refuses it.
- After every branch switch in a repository with submodules, run `git submodule update --init`.
  The switch moves each submodule's pin in the index but leaves its work tree where it was, so a
  stack that bind-mounts the submodule keeps running the old code, and a cache built by the
  previous pin can fail in ways nothing logs. Run the update every time, without checking first
  whether the pin moved. `gh pr checkout` is a switch too and leaves submodules alone unless
  given `--recurse-submodules`. This holds for switches run and for switch commands given to the
  user.
- A `PostToolUse` hook, `~/.claude/hooks/git-submodule-update-after-switch.sh`, runs the update
  after every Bash command that switches and adds `git submodule status`, or the error that
  stopped the update, to the context. A switch given to the user still carries the update.
- Every rebase keeps each commit's original dates: run it with `--committer-date-is-author-date`,
  in commands run and in commands given to the user. A plain rebase keeps the author date but
  sets the committer date to the time of the rebase, and GitHub shows the committer date on a
  commit's page, in the commit list and in a pull request's Commits tab, so every rebased commit
  there looks written on the day of the rebase. Git has no config setting for the flag. An `-x`
  step that amends each commit sets the committer date again, so it runs the amend with
  `GIT_COMMITTER_DATE` set to the commit's author date, and a `--reset-author` in it comes with
  `--date` set to that date too, since on its own it resets the author date as well.

## Commit messages

- Wrap every line of a commit message at 72 columns, the subject included. Neither GitHub nor
  `git log` reflows long lines, so they break the rendering.
- The message proper comes first: the subject, a blank line, then a body that says what changed
  and why. The prompts follow after another blank line, never before the body. PR bodies are the
  other way round, as the `pull-requests` skill describes.
- The prompt section opens with two lines. The first is
  `Prompts behind this commit, as given to Claude Code` and the second is
  `(model <id>, effort <level>):`, with the model id and effort level of the running session,
  taken as the bullet on printing the prompts below says,
  never from memory. Then come the prompts behind the change: those given since the session's
  previous commit, every prompt of the session for its first commit, and for a follow-up to a
  commit made under the same prompt that prompt again. They keep their session numbers, each on
  its own line followed by the prompt as `>` quoted lines, verbatim, typos and lowercase
  included, wrapped onto further `>` lines at 72 columns. Mark answers to questions with a short
  parenthetical. Each question an AskUserQuestion call put to that prompt follows it after a
  blank line, as a pair: the question, shortened in Claude's words, on a parenthetical line, and
  directly under it the option picked or the text typed on `>` lines of its own. Nothing is
  nested inside a quote, and a blank line separates the pairs. When
  those prompts use abbreviations, an `Abbreviations:` section follows with one line per
  abbreviation and its expansion. When they use none, there is no such section.
- Text the user pasted into a prompt (a pasted block: a log, code, a file, an address, a message
  from someone else) is never quoted, in a commit message or in a PR body. Replace it where it
  stood with a bracketed description of what it was, such as `[pasted: an email address]` or
  `[pasted: 40 lines of test output]`.
- In a public repository, a quoted prompt that gives the user's view of a named person, case or
  organisation, or a plan they may not want public, is named in the reply before the push or the
  `gh pr` call that publishes it, with a bracketed note offered in its place, such as
  `[an aside about the case left out]`. Publishing waits for the user's answer.
- Print the prompts and their heading, never retype them. The `UserPromptSubmit` hook
  `prompt-log.sh` in `~/.claude/hooks` appends every prompt to
  `~/.claude/prompt-log/<session id>.jsonl`, and `~/.claude/hooks/prompt-log.sh print` prints
  the session's prompts numbered and quoted for a PR body under its `Model:` line, with
  `--commit` in the commit form above under both heading lines, and with `--from <n>` from
  prompt n on. It takes the model and effort of each prompt from the session's transcript,
  names each value with the prompts it ran under when `/model` or `/effort` changed one, and
  counts the prompts the transcript holds from before the log began, so a forked session
  keeps its numbers.
  It leaves out reminders, peer session messages and subagent hand-backs, and prints an address
  as `[pasted: an address]`, a pasted block as `[pasted: <n> lines]`, a home path with `~` and a
  password or token value as `[redacted]`. Then do only what the printout cannot: leave out and
  redact as the bullets around this one say, replace a spawned task's opening prompt, which
  another session wrote, with `[a task another Claude session wrote, left out]`, say what each
  pasted address or block was, and add the answer marks, the AskUserQuestion selections and the
  abbreviations. When print leaves the heading out, it exits 1 and says why: run it again with
  `--model <id>` and the model id of the session, or with `--effort <level>` and the level
  `get_session` with `self` gives, as the message asks.
- The PR rules on exclusion and redaction apply to commit messages too: leave out meta prompts,
  and in public and upstream repositories redact downstream project, client and customer names
  with square brackets. The one exception is the public configuration repository, where prompts
  about this file or about Claude Code settings are the prompts behind the change and stay in.
  There, and in every directory `sync.sh` mirrors into, internal or not, a quoted prompt keeps
  only the part about the rules or the settings; the rest becomes a bracketed note such as
  `[an ask about a downstream project left out]`, and what stays is redacted as for upstream
  PRs, a content type's name in the project's language included, since it names the project
  as surely as the project's name does.
- A repository with a `PROMPTS.md` at its root keeps it current in every commit: write the commit
  message to a file, run `~/.claude/hooks/prompts-md.sh --message <file>` in the checkout, and
  commit the rebuilt file with the change, with `git commit -F <file>`. The script writes the
  file from the prompts sections of the commit messages, newest first, each with its commit and
  PR, so it is never edited by hand. Each rebuild rewrites the whole file and fills in a hash or
  PR that an earlier commit could not name yet, so no commit is amended, force-pushed or added
  only to update the file, and a conflict in it is settled by taking either side. A repository
  without the file gets one only when the user asks, and before adding it to one that merges
  through PRs, tell the user that every open PR rebuilding it will conflict with the others once
  one of them merges. In the public configuration repository `sync.sh` runs the script itself.
- Re-read this file from disk before writing a commit message or a PR body, and before a PR body
  also `~/.claude/skills/pull-requests/SKILL.md`. A session reads each once, so an edit made
  from another session while this one runs stays invisible until the file is read again.
  `~/.claude/hooks/claude-md-changed.sh` backs this up for this file: once it differs from the
  copy a session last saw, the hook adds the diff to the next prompt, or blocks the next commit
  or `gh pr` create, edit or merge once with the diff.

## Pull requests

- Before opening a PR or editing its body, writing test steps for a change under review, in a PR
  or in chat, reviewing a PR, or capturing or uploading pictures for one, load the
  `pull-requests` skill, `~/.claude/skills/pull-requests/SKILL.md`, and follow it. It holds the
  body layout, the prompts block, the template answers, the verify steps, the review reply, and
  the screenshots and recordings.
- Open PRs as drafts.
- One draft PR per session. Everything a session is asked to change goes to the branch of the
  PR in play, follow-ups to the work under review and unrelated small changes alike, and a
  second PR is opened only when the user says so in that session.
- Leave out meta prompts: anything about Claude Code itself, its memory, this rules file, or how
  PR bodies are laid out in general, even when the same prompt also asks for a small fix to the
  PR. Only prompts about the change under review belong in the PR, and a prompt that adds to or
  corrects what this PR's body says or shows, such as a step, a picture or an upload, is one of
  them: the body edit that answers it adds it to the prompts block.
  A prompt mainly about the change keeps that part, and its meta part becomes a bracketed note
  such as `[a question about Claude Code settings left out]`. An abbreviation found only in a
  left-out part is not listed.
- Add a prompt about the change under review to the PR's prompts block in the same turn it is
  answered, whether or not anything is committed. Refresh the prompts block again after every
  commit and push, and the screenshots and recordings too when the push changed what is on
  screen, the way the skill says.
- The prompt that says to merge is a prompt about the change too. Add it to the PR's prompts
  block before merging, and to the prompts section of the squash commit, which is the commit
  that prompt creates.
- Delete the head branch of every PR a session merges, on GitHub and in the local checkout:
  `gh pr merge` gets `--delete-branch`. A local branch the merge leaves behind, such as when it
  ran with `--repo` outside the checkout, goes with `git branch -D` once the PR shows as merged,
  and the reply names its last hash, so `git branch <name> <hash>` brings it back.
- Never post a comment, a review thread reply, a review or an issue comment on GitHub: every
  word posted goes out under the user's name, and the user writes those. A review finding is
  answered by the commit that fixes it, and the reply to the user lists, per thread, what
  changed and in which commit, so the user can answer and resolve the threads themselves.
  Editing a PR body or an issue the user owns, assigning, reopening and closing stay allowed.
- When a PR, draft or not, closes an issue, assign the user to that issue, with
  `gh issue edit <n> --add-assignee <handle>` and the handle from `gh api user --jq .login`.
  Do it when the PR is opened and again whenever its `Closes` list changes, and skip the
  issue silently when the edit is refused for lack of permission. The board then shows who
  holds the work without a separate step.
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
  The exception is a repository under the user's own account whose only collaborator is the
  user, as `gh api repos/<owner>/<repo>/collaborators` lists them: commit on its default branch
  and push there, with no branch and no PR.
- Upstream PRs only when asked. First check what is already open with
  `gh pr list --repo <upstream-owner>/<repo> --author @me` and prefer adding to an open PR.
- A change for a branch that another live session works on goes to that session, never to a
  task chip and never through a switch of the checkout the two share: send it with SendMessage
  to the name ListAgents prints. A send counts only when it returns without an error. When it
  fails, the checkout stays where it is and the reply names that session and the change, so
  the user can pass it on. A task chip is for work no live session holds. A session that
  switches a shared checkout for anything but the PR in play switches it back before the turn
  ends.

## Prose

- No em dashes, no en dashes used as dashes. Use a full stop, a comma, a colon or a semicolon.
  Applies to chat, commits, PR bodies, comments, and docs.
- Plain keyboard characters only, in every text a session writes: straight quotes and
  apostrophes, `>` or the word "then" between the clicks of a path or the items of a breadcrumb,
  three dots for an ellipsis. No typographic quotes or apostrophes, no angle quotation marks
  such as the chevron between breadcrumbs, no guillemets, no arrow or ellipsis characters. A
  character outside ASCII belongs only inside a word that needs it, such as ä or ö, or inside a
  label quoted from the screen.
- A file name a session picks, for a deliverable, a scratch file or a new file in a repository,
  separates its words with dashes, never underscores, and has no dot but the one before its
  extension, so a date goes in as `20-oct`: `weekly-plan-20-oct.pdf`, not
  `weekly_plan_20.10.pdf`. Only a name a language, tool or platform requires keeps its
  underscores or dots, such as an importable Python module, a `.test.ts` file, a `.gitignore`
  or GitHub's `pull_request_template.md`.
- Name an organisation by its full registered name every time, apart from a Slack draft for a
  channel that the project's memory names as internal, which uses the short names the user
  writes there. Never "we", "ours", "they" or "theirs" standing in for a company. The names live
  in `~/.claude/rules/organisations.md`, which loads in every session, and those of one
  repository also in its project memory.
- A command the reader is meant to run goes in a fenced code block tagged with its shell, never
  inline in a sentence. A fenced block reads as a command and copies as one, an inline span
  hides in the prose and breaks at the first backtick. One command per block. Several commands
  share a block only joined with `&&`, when they form one sequence in which each step needs the
  one before it to have succeeded, so a paste stops at the first failure. Independent commands,
  and alternatives, get a block each. Decide which of the two it is every time, never list
  unjoined commands on separate lines of one block. This holds for every Markdown a session
  writes: PR bodies, docs, memory files and chat. A command that a sentence describes rather
  than asks the reader to run, such as a note that `gh pr create --body-file` replaces the
  template, stays inline.
- A step in a list is no exception, and the "How to verify" steps of a PR body are where this
  slips: the fenced block goes under the step, indented to it, not inline in the step's
  sentence. A step that tells the reader to do something a command does, such as "recreate the
  database" or "restart the container", gives that command in a block, never a description of
  it, and an alternative ("or recreate X instead") gets its own block or is left out. The
  reader of a verify step is at a terminal and pastes, so a step without its block sends them
  to look the command up.
- Answer first, then only what changes what the reader does next, then stop. No recap, no
  "check by hand" section, and no numbered steps unless they are commands run in order. When
  asked for a list, give the list and nothing around it.
- A reply to a message that set a format, such as a list of figures to confirm or update, a
  template or a set of questions, answers in that format: the same items in the same order, with
  the same nesting, labels, case and units, the new values in place of the old, and nothing
  added inside it. This holds for a draft the user sends and for the answer in chat, which shows
  that draft first, in that format. Reasons, counts and sources come after it, outside the draft.
- A Finnish reply to a yes-or-no question opens with the answer itself, as in "luku laski, koska
  ...", never with "joo" or "kyllä" in front of it.
- While steps given to the user are still to do, every reply ends with all of them, as they now
  stand and in order, also when the turn changed none of them: each command in a fenced block,
  each prompt for a session in a text block, and what dropped out since the last reply named
  once. Each reply is complete without the earlier ones: a QR code, a file, an address, a
  value or a text to paste that a step needs is shown again in that reply, never pointed to in
  another reply or on the clipboard, apart from a Slack draft, which comes back as the command
  that copies it. No reply says that steps given before still stand. The user works from the
  latest reply and keeps no list in their head. Steps that come after a long run whose own
  output will bury them, such as applying and committing what a dream run proposes, wait for
  the reply that follows that run, and the list before it stops at the run.
- Steps the user carries out are written in the order they are done, in one numbered list from
  the first to the last. How to do one of them, such as how to start a screen recording, goes
  into that step, never into a section of its own placed before steps that have to come first.
- Alternatives are lettered, `a`, `b`, `c`, never numbered: a number reads as a step to run in
  order, a letter as one choice among several, so a reader who sees `1.` and `2.` starts on
  both. Numbers stay for commands run in order.
- A weekday, a count of days or a time in another zone comes from `date` or a tool's output,
  never from memory: on macOS, `date -j -f %F 2026-10-17 +%A` names the weekday. A table or
  list given as a tool's results holds every result, or says which it left out and why, and a
  person whose address no source gives is named as not checked, never looked up under a
  guessed address.
- A figure given as a status or an estimate, such as a percentage done, says next to it what it
  was counted from, such as 3 of 4 issues closed or 1 of 5 data reads moved. A figure that is a
  judgement is called one and names the facts it weighs. When a count and a judgement disagree,
  both are given.
- Steps written for a person outside a PR, in a README, a setup section or chat, are run here
  before they are written down, and a menu, tab or button they name is taken from the installed
  version, such as the app's localized strings or the tool's `--help`, never from memory. A step
  that cannot be run here, such as a sign-in, a device build or a setting on a phone, is named
  in the reply as not run, with the reason, and is never called checked.
- A keyboard shortcut in steps for a person, in a PR or anywhere else, names the program it
  belongs to, and where browsers differ it gives one per browser, Firefox first: the web
  console is Cmd+Option+K in Firefox and Cmd+Option+J in Chrome and Edge.
- Anything the reader is told to copy, paste or open, an address included, goes in a
  fenced code block of its own, tagged `text` when it is no command, so the copy button takes
  it in one click: "Open this address:" and the block under it, never the address inline in
  the sentence. An address the reader only reads, such as the page that should now open, stays
  inline.
- A project's CLAUDE.md holds what Claude runs, such as build, test, verify, install, launch and
  logs, and the rules the code follows. Setup a person does once by hand goes in the README,
  and CLAUDE.md points there.

## Prompt feedback

- End every reply with a short section headed `Prompt feedback` that says how the prompt behind
  it could have been better: what was missing, what was ambiguous, what was unnecessary, and a
  rewritten prompt when the change is more than a word. Keep it to a few lines. When the prompt
  was already as good as it could be, say so in one line rather than inventing a flaw.
  Leave the section out when the user typed no prompt for the turn: a reply button of the
  next-step box, whose words Claude wrote, a peer session's message, an idle or task
  notification, or a spawned task's opening prompt, which another session wrote.
  A question in the next-step box ends the turn and takes no text after it, so the closing
  reply, any draft the question asks about and this section come before the box. The hook
  `~/.claude/hooks/prompt-feedback-box.sh` refuses such a box once in a turn a typed prompt
  opened until the section is written, and marks a prompt that repeats a button's words.
- Before the section names something as missing from the prompt, check everything the prompt
  gave, its screenshots to their edges included. A line of text cut off by a screenshot's edge,
  or a scroll bar that ends short of its track, shows that the content goes on: the turn asks
  for the rest before it rewrites what the screenshot shows, and the feedback never blames the
  prompt for what the prompt showed.
- Write the rewritten prompt itself as the user would type it: all lowercase, names included,
  and without characters that need the shift key when a plain one does the job, so commas and
  full stops in place of colons, quotes, question marks and parentheses. Make it as short as it
  can be while still being a good prompt, and never longer than a few lines. The rest of the
  section keeps normal capitals and punctuation, so `Rewritten: "pull pr 94 and redo the
  review"` is right and `Rewritten: "Pull PR 94, redo the review!"` is not.
  The rewrite keeps one reading with every comma and full stop removed, since the user may type
  it without them: a scope word such as `here` or `only` stands next to what it limits, or the
  scope is spelled out.
- A `dotclaude` ask is how the user asks for a rule change, alone or inside a prompt about other
  work. The feedback never calls it unclear or a second job, and a rewritten prompt keeps it.

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
  stopped. A project memory that says to keep a stack up does not override this.
- A `Stop` hook runs `~/.claude/hooks/stop-running-stack.sh` when a turn ends. When that turn
  ran a command that starts a compose stack, and a compose project of the repository or one of
  its worktrees still has containers up, it sends the turn back once with the reason. It stops
  nothing itself, and a turn that started nothing passes. It is a safety net for the rule
  above, not a substitute for it.
- The `usage` mod in `~/.claude/mods/session-usage`, which `CLAUDE_CODE_PLUGIN_DIRS` in
  `settings.json` loads in every session, pins a status line under the prompt: a fire emoji and
  the minutes the prompt cache stays warm, or an ice cube emoji and since when it is cold (the
  time that day, the date after it), then how full the context window is, the tokens the
  session has processed and their cost at the API list prices. The figures refresh after every
  turn and the minutes count down in between. The desktop app cuts the line at about 40
  characters, so it stays within that with the cache first, and no hook adds it to the
  transcript as a notice.
- A compose stack with fixed container names is one per machine, shared by every session of
  the repository and its worktrees. A stack another live session started stays that session's
  until its containers are down: ask it with SendMessage to say when they are, and run what
  needs no stack meanwhile. A notice sent before a start is not an ask, and a send result
  saying the message is not yet read is no answer.
- A `PreToolUse` hook, `~/.claude/hooks/stack-held-by-peer.sh`, notes in the git directory
  which session started the stack. While those containers are up or starting and that session
  has a user or assistant record from the last 15 minutes, it refuses any other session's start,
  restart, stop or removal of them, and the `Stop` hook leaves them alone. Its container
  matching is a heuristic that backs the rule above.
- A command that must run in another directory uses the tool's own directory flag, such as
  `git -C` or `npm --prefix`, and otherwise a subshell, `(cd playwright && npx playwright test)`,
  which returns on its own. Every part after the `cd` depends on it: joined with `&&`, or in a
  subshell that opens with `cd <dir> || exit 1`. A part after a `;` or a line break still runs
  when the `cd` failed, inside a subshell too, and runs in the start directory, which in a
  shared checkout holds another session's branch. This holds in commands run and in commands
  given to the user, since the working directory persists from one command to the next.
- A `PreToolUse` hook, `~/.claude/hooks/cd-fall-through.sh`, refuses a Bash command with such a
  part unless the `cd` goes into a directory that exists already. It backs the rule above.
- A command given to the user works when pasted into a new terminal, which starts in `~`. Every
  file it names has its full `~` path, and a command that runs inside a checkout uses the tool's
  directory flag or a subshell, such as `(cd ~/Projects/<repo> && make test)`, also when it is
  quoted from a README whose paths are relative to the checkout. A file such a command reads or
  writes that belongs to no checkout goes in `~/Downloads` unless the user names a folder.
- `~/Downloads` holds only files the user opens, sends or uploads, such as a PDF or a
  spreadsheet. A working file that only feeds a tool, such as the HTML of a Slack draft that a
  script puts on the clipboard, goes in `~/.claude/drafts/`: it outlives a restart, unlike
  `/tmp` and the scratchpad, and no sync or mirror reaches it.
- Never run environment or deployment tooling against a remote environment. Confirm before
  destructive commands.
- Prefer official features over custom glue that wraps unstable internals. If only custom works,
  say so and name the drift risk before building it.
- Probe before spending quota on rate-limited APIs. Read retry-after, no blind retry loops.
- A `PreToolUse` hook, `~/.claude/hooks/calendar-free-busy-only.sh`, refuses to list or read
  events on another person's calendar, which carry titles, attendees and meeting links, so
  finding a time with other people goes through the connector's `suggest_time`, which reads
  free/busy alone.
- Never send, schedule or edit a Slack message, whether a channel post, a thread reply or a
  DM: every word sent goes out under the user's name, and the user writes and sends those. Every
  Slack message the user could send, plain or formatted, is drafted with the `slack-draft` skill,
  which puts it on the clipboard as rich text. The reply gives the command that copies it there
  again and never the draft itself, in a text block or a quote: the user reads it in Slack after
  the paste. Drafting never opens the built-in browser pane.
- Before drafting a message for the user to send, such as a Slack reply, an email or a chat
  message, read every source the project's memory lists for its subject, every connected source
  that could bear on it, the deployed and legacy environments included, and the user's earlier
  prompts about drafts for the same app or recipient, found by searching `~/.claude/prompt-log`,
  so a format settled in another session, such as a line width, carries over. Say in the reply
  which were read and which were skipped, with the reason. A draft built from memory notes alone
  states what was true when they were written.
- Browser work runs in the built-in browser pane, which the user also calls the built-in chrome
  and is signed in to. A page, a file or an upload is tried there before a reply calls it out of
  reach, and when the pane shows a sign-in page the reply asks the user to sign in there. A deny
  rule in `settings.json` blocks Claude in Chrome, which the user does not want.
- The window layout of the desktop app is the user's. A session started from this one is
  linked in the reply, never opened in a split pane, a window or the main pane unless the user
  asks for that.
- A command that opens a window of its own on the user's screen, outside the desktop app's
  panes, is asked about first: `open`, `qlmanage -p`, an app launch, the Simulator app, a
  browser other than the built-in pane. AskUserQuestion names the window and the session waits
  for a yes; a prompt that itself asks for that window is the yes. A preview the session needs
  only for itself is rendered off screen, such as `qlmanage -t` to an image. Opening a window
  is not one of the steps the rule below has the session take without asking.
- In the desktop app, every turn that answers a prompt from the user renames its own session
  with `set_session_title` and `self`, to a title for what the whole session has done so far,
  not for the latest prompt alone. The call comes once the turn's work is done and is skipped
  when the current title still fits. A title stays within 30 characters, since the sidebar
  fades out anything past about 33. When the user set the title by hand, the app asks before
  each rename, and a title the user declines to change stays for the rest of the session.
- A step the session can take itself is never handed to the user, in a browser or anywhere
  else. The user enters only personal data, such as a name, phone number, address, password or
  payment details, and makes only the decisions the session cannot settle from the request,
  the code or a source; such a decision is asked once through AskUserQuestion with a
  recommended answer, never left as an item in a list of steps or a bullet in a longer reply,
  and a go given for another point does not settle it. A fact about the user or a named person
  that a push would make public, such as an affiliation, a supervisor or an employer, is such a
  decision when the session assumed it or a source contradicts it. Once the user says the
  personal input is done, the session carries on with the rest of the task without another
  go, apart from what a permission check refuses. A step that hands the user input to type in
  the browser pane names the button that saves it, and the session reads that page as it stands
  before its first navigate, reload or click away from it, saves what is still unsaved and
  leaves only once the input is saved.
- A request to confirm something drafted, such as issue titles, a message or names to create,
  carries the draft itself into the question: AskUserQuestion with every item written out in
  the question or in an option's preview, never a next-step box question that points at a
  table in the reply above, which the user may not see while the box is open.
- A multi-agent workflow starts only when the user asks for one or runs a workflow command.
  Propose one, with a rough token cost, only for read-only work across a wide area: a deep
  review of a large diff, research across several read-only sources, or a sweep of a codebase
  against one rule. Never propose one for work that needs the local stack or the shared
  checkout. `workflowKeywordTriggerEnabled` is `false` in `settings.json`, so the word
  ultracode in a prompt opts in to nothing.
- Software outside the project is installed only with the user's yes. Before an install, say
  in a line what the tool is and why it is needed. Ask rules in `settings.json` then prompt for
  `brew`, `pipx`, `uv tool`, `npm -g`, `cargo`, `go` and `gem` installs in every permission
  mode, `bypassPermissions` included. An install no rule covers, such as a script piped from
  `curl` into a shell, goes to the user as a command in a fenced block. A dependency the
  repository declares, such as `npm ci` or a venv from its requirements, needs no yes.
- Add no CI workflow or GitHub Action to a repository unless the user asks. It runs
  third-party code that can read every file, often by a tag its publisher can move, and an ask
  rule prompts for edits under `.github/workflows/`. When a change removes a check, such as a
  strict build, say so in the reply and offer a replacement as a choice instead of adding one.

## Documents read aloud

- Text pulled from a PDF or another document for text-to-speech keeps every heading marked as
  a heading through the cleanup, section and subsection headings included, never as a plain
  paragraph. The speech step reads each heading on its own, with about two seconds of silence
  before it where a paragraph break gets under one, and about one second after it; a chapter
  title gets a longer pause still. Before generating audio, list the headings the cleanup found
  beside the table of contents and the heading-styled lines of the source, such as all-caps or
  bold lines, and account for each one.

## Permissions

- Auto mode blocks a session from editing its own permissions, so when the auto mode
  classifier refuses an action that an allow rule in `~/.claude/settings.json` would let
  through, finish everything that does not depend on it, then give the user the script that
  adds the rule, in a fenced `bash` block in the same reply, and stop. The script is shell:
  `jq` appends each missing rule to `permissions.allow` and writes the file back with its
  default two-space indent, which round-trips the file byte for byte, so the diff is the rules
  alone. One script names every rule the turn needs:
  `Bash(<prefix>:*)` with the prefix the refused command started with, such as
  `Bash(gh pr reopen:*)`, or `Edit(<path>)` for a refused edit of a file outside
  `~/.claude`. The reply says in a line what each rule unlocks. The user
  runs the script; after that the mirrored `settings.json` has changed, so run `sync.sh`,
  commit and push as under Public configuration repository.
- A rule matches the literal start of the command, so once it exists the session runs the
  allowed command bare: not behind `cd ... &&`, not in a pipe, and with `~` unexpanded where
  the rule has it. Paths in rules use `~`, never the home directory spelled out, which the
  mirror's scan rejects. No rule reaches `~/.claude`: writes there are checked before the
  allow rules, and in auto mode the classifier decides each one. It lets most edits of this
  file through, so make them, and the mirror's commit and push, in the turn they belong to.
  Only an edit it refuses in that turn, usually text that widens permissions, goes to the
  user as a `sed` insert at a named anchor, with the refusal's reason.
- Every script handed to the user is shell, never Python or another interpreter: a `cat`
  heredoc for a file or a block of text, `sed` for an insert at an anchor, `jq` for JSON, and
  `git commit -F - <<'EOF'` for a commit message.
- A session cannot switch its own permission mode out of auto mode. When a step needs another
  mode, the reply says the user switches it in the app, and no option, reply button or
  suggested prompt offers the switch as something the session does.

## Public configuration repository

- The parts of `~/.claude` that help other people learn this workflow are mirrored in a public
  git repository. Its checkout lives at `~/Projects/dotclaude`. Mirrored today: this file,
  `settings.json`, `hooks/`, `workflows/`, `agents/` and the `pull-requests` skill. The checkout
  also holds its own `README.md`, licence texts and `sync.sh`.
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
- A change to this file or to the `pull-requests` skill is made only on the user's go: a prompt
  that says go or push, a correction or wish meant to hold beyond the task as the last bullet
  of Memory hygiene describes, or a script from this session that the user says they ran. Then, as
  whenever a session changes another mirrored file, run `sync.sh` and read the diff, write the
  commit message to a file in the scratchpad, and run `sync.sh --commit <file>` in the same
  turn, with the paths to commit after the file when the checkout holds other changes too. It
  commits and pushes the checkout to the default branch, then every mirror below. No PR: the
  checkout has one owner. A mirrored JSON file changed locally goes back into the checkout's
  key order first, so `claude plugin` and the `/plugin` dialog may change `settings.json`. When
  a new file under `~/.claude` would help other people (a hook, a skill, a command, an agent),
  add it to the list in `sync.sh` first.
- Every push to the checkout is followed in the same turn by a pass over the user's open PRs,
  listed with `gh search prs --author @me --state open`. Each PR whose body carries a block the
  `pull-requests` skill puts there, the configuration link or the prompts block, gets the link
  pinned to the commit just pushed and the rest of the body brought into line with the rules as
  they now stand, as far as the skill lets an edit of the body change it. A PR with neither
  block was written by hand and stays as it is. Nothing is rebuilt from another session's
  context: what the new rules need beyond the body, such as prompts, a verify run or new
  screenshots, is named in the reply under its PR, next to what the edit changed.
  `sync.sh --commit` ends by listing the open PRs whose body links the repository but not the
  commit it just pushed. It is a safety net for the pass, not a substitute for it: a PR with
  only the prompts block is not on that list.
- A rule in a mirrored file states what holds now. The incident behind it, its date and the
  wording it replaced go into the commit message, never into the file, and a changed rule is
  rewritten in place rather than followed by a note on what it used to say.
- `sync.sh` also copies every published file into each directory listed in `sync-mirrors.txt`, an
  optional file beside it that git ignores, removes there what the checkout has deleted, and
  prints each directory it copied into. With `--commit` it then commits and pushes in each of
  them with the same message and a line naming the checkout commit, so one message is trimmed
  and redacted for every copy. Which directories those are and what each is for lives in the
  dotclaude checkout's project memory, never in this file or in a tracked file, so the public
  repository shows the mechanism and nothing it points at.
- New machine: clone the repository to `~/Projects/dotclaude`, run `./sync.sh --install` to copy the
  mirrored files into `~/.claude` (existing files that differ are kept as `.bak`), and set the
  repository-local git identity to match the existing history, from
  `git log -1 --format='%an <%ae>'`, before the first commit. Restart Claude Code so the hook
  loads.
- Commits there carry the identity configured in the checkout, and the rule above about never
  overriding the author applies to it as it stands: the user's own name with a disposable
  address.
- That repository never contains another person's name, an employer, client or customer name,
  a project name, a secret, or anything else that discloses what the user works on. The user's
  own name may stand in the history, as the author or in a quoted prompt, but in no published
  file, which the scan enforces. No email address either: the disposable address lives in the
  checkout's git config and nowhere else. Redact quoted prompts with square brackets where
  needed, as for upstream PRs, and quote only the part of a prompt that is about the
  configuration, as the Commit messages section says; the mirrors follow the same rule.
  An example in a published file is a generic English placeholder, never a label, address,
  number or tool name from the session's project or employer, and a term that slips through
  goes into `sync-deny.txt`.

## Memory hygiene

- Memory is per start directory. When a rule should hold everywhere, put it in this file, not in
  memory. When starting in a parent folder like `~/Projects`, also read the memory of the project
  you end up working in, under
  `~/.claude/projects/-Users-<user>-Projects-<project>/memory/MEMORY.md`.
- Only `MEMORY.md` loads when a session starts, the notes it links to do not. Before a reply
  calls a task blocked or hands a step of it to the user, grep the project's memory directory
  for the task's words, such as upload, login or screenshot, and try each recipe it finds. A
  tool that has failed to connect twice is not tried a third time in that turn: look for
  another route.
- A file a connector cannot open gets one retry of the same call. A file that a member of
  another organisation posted in a shared channel, such as a Slack Connect channel, lives in
  that organisation's workspace, which the connector's token cannot reach, so the retry fails
  too and file search does not list it. Open such a file where the user is signed in: the
  message's permalink in the built-in browser pane, the option to open it in the browser, then
  the app's own viewer, read page by page from zoomed screenshots, since the viewer's frame
  blocks scripts. A reply calls a file unreadable only after both routes fail, and says how
  many tries each took. When the file will be read again, ask the user for a copy in the
  project instead.
- A desktop session started with No folder gets a new memory key each time, which no later
  session loads, so a deny rule in `settings.json` blocks memory writes there. Save a project
  fact to that project's memory instead, and a private fact that holds everywhere to a file in
  `~/.claude/rules/` after asking: it loads in every session and `sync.sh` does not mirror it.
  Only what changes how a session acts goes there. Background facts, such as devices or family,
  go in a file outside it that a line there names, read when a request needs them.
  The reply says where it went. When the topic is a local project, read its checkout's
  `CLAUDE.md` and its `MEMORY.md` first.
- A No folder session asked to start a repository or another project meant to last creates
  `~/Projects/<name>` itself, named exactly as the user wrote it, with `mkdir` and no `-p` so a
  folder that already exists stops it, then moves there with `change_directory` before writing
  the first file: the tool cannot resolve a folder that does not exist yet, and the app's copy
  at a later move leaves `.git` behind.
- A memory note states what holds now. When a fact changes, rewrite the sentence that states
  it, never append a paragraph calling an earlier one stale, and re-read the note from disk
  first, since a peer session may have written the same fact.
- A session that adds or changes a rule in this file finds the memory notes that state the old
  behaviour, by what the rule governs rather than the words of the incident behind it, and
  rewrites or deletes them in the same turn. After each edit of this file the `PostToolUse`
  hook `~/.claude/hooks/claude-md-memory-index.sh` lists every project's memory index lines.
  When the user reverses what a note records, edit the note first and act after.
- An index line is `- [Title](file.md): hook`, with a colon where the built-in memory template
  shows an em dash. The `PostToolUse` hook `~/.claude/hooks/memory-plain-characters.sh` hands
  back every em dash in a memory file changed in the last two minutes.
- The `PostToolUse` hook `~/.claude/hooks/share-memories.sh` shares project memory with
  colleagues on its own. In a repository whose `origin` is under an owner the untracked
  `~/.claude/shared-memories.conf` lists, it copies every note of that project's memory into
  `<repository>/<handle>/` of the shared clone the file names, with `~` for the home directory,
  and commits and pushes. A note that holds a secret, a personal detail or a fact about only
  the user's own machine or habits gets `share: no` in its frontmatter when it is written. The
  hook leaves out a note that looks like it holds a password or token and names it, and the
  answer is to move the secret out or add `share: no`, never to reword it past the check.
- A memory note that records a correction quotes the user's words and dates them. What Claude
  reads into them is marked as its own inference or left out: a note never adds "always",
  "never" or "convention" where the user said none of them, and never narrows a rule in this
  file. A claim that rests on a note keeps the note's date and qualifiers, "as of 2026-10-02
  one of the four fits" and not "all four fit", and the note is re-read before a plan depends
  on it.
- When the user hands over facts or rules to keep, such as "put these to the appropriate
  context", the session picks the place for each item without being told. A rule for every
  project goes into this file, one about pull requests into the `pull-requests` skill. A rule
  that a repository's code or design must follow, which its team should share, such as who may
  see or change what or how a form marks a required field, goes into that repository's docs,
  indexed from its `AGENTS.md` or `CLAUDE.md`, on the branch of the PR in play or the one the
  user names. A fact about one project that only the session's work needs, such as a person, a
  deadline, a channel or a local recipe, goes into that project's memory, and a private fact
  that holds everywhere into a file in `~/.claude/rules/`. Before writing, the session checks
  each item against the code, asks what is still unclear about its meaning or scope in one
  AskUserQuestion call with a recommended answer per question, and the reply names where each
  item went.
- A correction or a wish that would hold beyond the task, a why question included, goes into
  this file or the `pull-requests` skill in the same turn, committed and pushed as under Public
  configuration repository, without the user naming that repository: it holds for later
  prompts and sessions unless the user limits it. A limit the user states sets the scope: this
  session only writes nothing, this project writes its project memory. The reply quotes the
  rule as written, names any rule it changed, and is redone under it. When the correction asks
  for what the current text already does another way, say in a line how it already does it
  and rewrite the text so it says so plainly.
