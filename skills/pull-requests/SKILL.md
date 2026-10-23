---
name: pull-requests
description: Procedures for a pull request. Load it before opening a PR or editing its body, before writing test steps for a change under review in a PR body or in chat, before reviewing a PR, and before capturing or uploading screenshots or recordings for one. It covers the body layout, the prompts block, the template answers, How to verify, manual steps, the review reply and the pictures.
---

# Pull requests

These procedures sit beside the Pull requests rules in `~/.claude/CLAUDE.md`, which still hold:
drafts only, one PR per session, never post on GitHub, meta prompts left out, and downstream names
redacted in public and upstream repositories.

## The body

- Claude's part of the body is, in this order: the one sentence on what has changed, the line
  that closes issues (`Closes #n`, with any related documents), the two blocks below, then the
  rest of the repository's pull request template filled in as described further down. Nothing
  else: no free-form summary or test plan outside that. The sentence and the closing line stand
  on their own, without a heading, even where the template gives them sections of their own.
  Without a template the body ends after the blocks and the user writes the description.
- The two blocks come straight after the closing line and above the rest of the template. They
  are a TL;DR for the reviewer.
- First block: a fenced code block holding the URL of the public configuration repository
  described under Public configuration repository in `~/.claude/CLAUDE.md`, pinned to a commit
  as `<repository URL>/tree/<full hash>`, so teammates can read and copy the rules the body was
  last checked against, not ones changed since. Take the repository URL at runtime from the
  checkout's `origin` remote, with `git -C ~/Projects/dotclaude remote get-url origin`,
  rewritten from the SSH form to https and without the `.git` suffix, and the hash from
  `git -C ~/Projects/dotclaude ls-remote origin HEAD`, the commit GitHub serves as the default
  branch, never from memory or from a local commit not pushed yet. Every edit of the body takes
  the hash again, and every push to that repository edits each open PR that carries the block,
  as Public configuration repository in `~/.claude/CLAUDE.md` says, so the block names the
  commit current at the body's last edit. A code block and not a Markdown link: a link's
  visible text can differ from where it goes, while a URL the reader pastes is one they see in
  the address bar before they go.
- Second block: `<details><summary>Prompts behind this PR</summary>`. Its first line names the
  model and effort level the session ran with, for example `Model: claude-fable-5-1, effort:
  medium`. Take them, and the prompts under it, as the bullet on printing the prompts under
  Commit messages in `~/.claude/CLAUDE.md` says, never from memory. Then number every prompt
  from the session in order and quote each verbatim, typos and lowercase included, as a `>`
  blockquote (`**1.**` on its own line, then the `>` quote). Include prompts that produced no
  commit. Mark answers to questions with a short parenthetical, and put AskUserQuestion
  selections as nested `>` lines under the prompt.
- Directly under the model line, before the first prompt, a nested
  `<details><summary>Abbreviations</summary>` block lists every abbreviation used anywhere in the
  quoted prompts with its expansion, one per line, so a reader who does not know one can open
  the list and check. When the prompts use none, leave the block out.
- Pasted text inside a quoted prompt is replaced by a bracketed description, as the commit
  message rules say. The prompts may come before the rest of the body here, unlike in a commit.
- Below the blocks, fill in the rest of the repository's pull request template when it has one.
  Look in `.github/` for `pull_request_template.md` or `PULL_REQUEST_TEMPLATE.md`, a
  `PULL_REQUEST_TEMPLATE/` directory, and the same names at the repository root and under
  `docs/`. Keep the template's headings, comments and order, apart from the summary and the
  issue links, which go to the top as above, and answer each section briefly, such as the
  manual steps a reviewer follows to verify the change in the running app. A section
  that asks a yes/no question with a checkbox for each answer, such as "Added tests?" or "Is
  documentation up-to-date?", keeps only the box that applies, ticked, and the other box's
  line is deleted rather than left empty: nothing more when the answer is yes, one sentence
  saying why when it is no.
  `gh pr create` applies the template only when it composes the body interactively. `--body`
  and `--body-file` replace it silently, so the body file has to contain the template text.
- To change the body, read the live one with `gh pr view <n> --json body --jq .body`, edit it as
  a file, write it back with `gh pr edit <n> --body-file`, and re-read to confirm. Outside the
  blocks, change only a template answer that a later commit made wrong or left incomplete, and
  keep every edit the user has made there.
- After a commit that answers review threads, read How to verify against each thread. A fix
  that changes what a reviewer sees or does gets a manual step, or a sentence in the step that
  already shows that screen, and the summary sentence is rewritten when it no longer covers
  the PR. A fix nothing on screen shows needs no step.

## How to verify

- Test steps for a change under review, in a PR body's "How to verify" or given in chat, end
  with the last check. No step switches the checkout back to the branch it was on before: the
  next review's checkout replaces the branch anyway, and where to go next is the reader's call.
  Automated checks come first, the verify command and then end to end, and the manual pass comes
  last, unless the user says otherwise: a failing spec shows before the slow part, and end to end
  never follows the manual steps.
- The automated part is two command steps, each one fenced block joined with `&&`, since each
  is a sequence that should stop at its first failure. The first, run in a tab of its own,
  fetches, switches to the branch, updates the submodules and starts the stack. The second, in
  another tab, runs whatever the stack needs after a switch (a cache clear, a build), the
  verify command and the end to end run. The manual steps follow them.
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
  shortest name that works, a, b, c or 1, 2, 3, never a prefix such as the PR's number, unless
  a screenshot or recording of that step shows other data: then the step has the reader type
  and pick exactly what the picture shows, so the screen matches the picture. A step
  that searches by name says what to type and uses the shortest string the seed data does not
  contain, checked with a search in the grid first. Every action the reader takes is written
  down, also the ones that feel obvious: copy the address before pasting it, open the new tab
  before pasting into it, log in again after logging out. A step never relies on something the
  reader has not been told to do. A step that opens a page gives its full local address, such
  as `http://localhost:3000/items`, in a `text` block of its own under the step, never the
  page's name alone and never inline, so the reader copies it in one click instead of hunting
  through the navigation. Steps run in the order their data needs, deletions last. A
  step that uses a seeded record says it comes from the seed and what to type to find it. Where
  the screen shows a stand-in, such as placeholder data, a mock or an unwired part, or a part
  that ignores the step's input, the step says so. A limitation found while building goes into
  its step, not only into the reply.

## Reviewing a PR

- A PR review switches the checkout to the PR's branch and leaves it there, runs the two command
  steps above itself, and opens the reply with the results of the verify command and the end to
  end run, followed by the findings. "Here" or "only" in a review prompt limits where the reply
  goes, never what runs. Then comes one numbered list the reader follows from a cold start: the
  two command steps, each with its block under it, then the PR's own manual steps in the
  standing form, taken from the screen and no wider than the PR's steps plus the changes those
  steps skip, never a test script of the reviewer's own. A manual step that runs a command
  carries that command in a block under it, never a description of it. Where the PR's step has
  a screenshot or video, the matching step names it at its start, "the PR's screenshot under
  step 3 shows this dialog", and the comparison comes before the click that closes what the
  picture shows. Open every such picture at full size before writing its step, and take the
  step's typed and picked values from it.
- Each finding carries its severity, high, medium or low. Every finding that is not low gets
  the shortest reproduction that shows it, so the reviewer can send the author back to fix it
  before reviewing anything by hand: from the stack running the PR's branch on its seed data,
  the fewest numbered steps that bring the bug out, then what happens, what should happen
  instead and, when the review found it, the code that causes it, as GitHub markdown in a
  fenced block under the finding. The reproduction is run here as written before it goes in.
- Every bug the review finds has a step in that list where the reader sees it: the step that
  reaches the state, or one added for it right after the step that does, opens with "Bug
  (finding n):", gives the clicks that bring the bug out, then what the screen shows and what it
  should show instead. The finding names that step in turn, so the reader can go from either to
  the other. The bug's step undoes any change the later steps do not expect. A bug nothing on
  screen can show, such as a race or a path no click reaches, says so in its finding.
- The list ends with what the PR's instructions missed, or a line saying nothing was: a label
  that is not on screen; a click left out; a step the seed data cannot do, or state the reviewer
  builds by hand through a workflow the specs already cover, which the PR should have seeded; a
  change without a step; a check that failed or a claim the run disproved; a picture placed
  after the step it shows. That section ends with the two command steps of the list as GitHub
  markdown inside a four-backtick fence, numbered as in the reply, so the PR's "How to verify"
  can take them over unchanged. That block is the one thing in the reply written for the PR's
  body, as the reproductions are the ones written for its author.

## Screenshots and recordings

- Screenshots and recordings go into the PR body when the change is visual, anything that
  alters what a page renders, and the repository asks for a recording or screenshots, in its
  pull request template or in the agent instructions it keeps in context (`AGENTS.md`,
  `CLAUDE.md`). A repository may keep such asks out of the template so the body carries only
  what a reviewer reads, and they bind as much there.
- Capture them from the local stack on fixture data with a scratch Playwright script in the
  scratchpad, on the repository's Playwright install, never a config change in the repository:
  one PNG per manual step of "How to verify", in the state that step describes, named after the
  step, and a WebM only where motion is the point. A recording is made with `slowMo` of about
  400 ms on the browser launch and a pause of two or three seconds at every state a step
  describes, since a Playwright run at full speed is too fast to follow. Fixture data is what
  the project's own start command leaves, so capture on a stack that no end to end run has
  touched since its last clean start: specs add records the reader's stack lacks.
- Open every picture with Read before it is uploaded, and check that it shows the state its step
  describes and nothing a freshly started stack would not show.
- Whenever screenshots or recordings exist for a PR and show what it changes, upload them to it
  in the same turn they are made, without asking first: a reply never ends with a set waiting
  for a go. Upload them through GitHub's own editor, where the user is signed in: drop the files
  into the PR's comment box, copy the markdown GitHub puts there, and clear the box without
  posting. The app's built-in browser pane has no file upload tool, so run
  `~/.claude/skills/pull-requests/pane-upload.sh -C <checkout> push <file>...`. It pushes the
  files on a throwaway branch and prints the JavaScript to run with `javascript_tool` on the
  PR's page, which returns the markdown and clears the box, then `pane-upload.sh clean <branch>`
  deletes the branch. An error from the JavaScript is never worked around: a pane signed out of
  GitHub waits for the user to sign in, and text already in the box is the user's and stays.
- Each picture goes at the start of the step it shows, never on the line with the number: that
  line holds the number and one short clause naming what the picture shows, the picture follows
  on its own line under it, indented to the step, and the step's text comes after the picture,
  so the reader sees what to look for before acting. A recording goes the same way under the
  first step it covers, as a bare attachment URL on its own line, which GitHub renders as a
  player where a `[name](url)` link does not. Write the body back with `gh pr edit`.
- Redo the set after every push that changes what is on screen, the way the prompts block is
  refreshed, so no reviewer judges a stale picture.
