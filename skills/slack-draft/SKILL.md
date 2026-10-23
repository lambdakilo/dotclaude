---
name: slack-draft
description: Draft a Slack message for the user to paste and send themselves, with link text, bold, lists and code kept. Load it whenever a Slack reply, post or DM is drafted, and whenever the user wants a draft formatted for Slack or with links in it.
---

# Slack drafts

Claude never sends a Slack message, as `~/.claude/CLAUDE.md` says. It drafts, and the user pastes
and sends. The CLAUDE.md rule on reading every source before drafting still holds.

## Why the clipboard

Slack's message box turns neither `[text](url)` nor `<url|text>` into a link. That syntax works only
through the API. By hand, link text gets in only by pasting a URL over selected text or by pasting
rich text. A draft for a channel that the project's memory names as a clipboard channel therefore
goes on the clipboard as rich text, plain ones too, and the user sends it with one paste.

Every other draft, and every draft outside a project that names such a channel, is only a fenced
`text` block in the reply, with each link as its bare URL after the words it belongs to: no HTML
file, no clipboard and no copy command. The user copies it from the block.

## Steps for a clipboard channel

1. Write the draft as an HTML fragment in `~/.claude/drafts/<topic>.html`, with words separated
   by dashes, starting with `<meta charset="utf-8">`. Write it with a `cat` heredoc in Bash,
   never with the Write tool: the desktop app opens an HTML file the Write tool writes in the
   built-in browser pane, which a draft never does. The HTML only feeds the clipboard, so it
   stays out of `~/Downloads`, which is for files the user opens or sends. Use only what Slack
   keeps from a paste: `<p>`, `<b>`, `<i>`, `<code>`, `<a href>`, `<ul>` or `<ol>` with `<li>`,
   `<blockquote>` and `<pre>`. A bold label opens each list item, unless the message being
   answered set a format: then the draft copies it, as `~/.claude/CLAUDE.md` says under Prose.
2. Link the evidence a claim rests on inline, on the words that make the claim, never in a
   parenthetical after them, and pinned so the link still shows what the text says later. An
   identifier the text names, such as a table, a route, a class, a file or a tag, is `<code>`,
   and a code thing it names, a page of an app included, links to the lines that define or
   serve it:
   - a commit cited for what it changed: `https://github.com/<owner>/<repo>/commit/<full sha>`
     on its subject line, placed in the sentence ("commented out in commit <subject>"), never
     "(commit `abc1234`)". A commit named as a version keeps its short hash as code text.
   - lines of a file: `https://github.com/<owner>/<repo>/blob/<full sha>/<path>#L<a>-L<b>`, with
     the sha of the commit that was read, never a branch name
   - a release: `https://github.com/<owner>/<repo>/releases/tag/<tag>`, the tag as code text
   - a pull request or an issue: its full URL, never a bare `#123`
   - a Figma frame: `https://www.figma.com/design/<file key>/<slug>?node-id=<a>-<b>`
   - a Slack message: its permalink from the Slack connector

   Check each GitHub link with `gh api`, the `contents` endpoint with `?ref=<sha>` for a file,
   the `commits` endpoint for a commit and `releases/tags/<tag>` for a release. Never name a
   shell variable `path` in that loop: zsh ties it to `PATH`.
3. Run the copy script. It prints what it read back and exits non-zero when a type is missing.
   ```bash
   ~/.claude/skills/slack-draft/copy-rich.sh ~/.claude/drafts/<topic>.html
   ```
4. In the reply, show the draft as a fenced `text` block so it can be read in the chat, with
   each `<code>` span in backticks and each link's text in square brackets, so the block shows
   what Slack will format and link. Say it is on the clipboard, and name each link the
   recipients may not be able to open, such as a private repository or a permalink from another
   workspace. Then the steps: paste with Cmd+V in Slack and check it before sending, and the
   command that puts it back on the clipboard once something else overwrote it, with the draft's
   own file name in place of `<topic>`:
   ```bash
   ~/.claude/skills/slack-draft/copy-rich.sh ~/.claude/drafts/<topic>.html
   ```

## What does not work

- AppleScript's `set the clipboard to` with HTML data writes HTML alone, and most paste targets
  then find nothing.
- A paste into Slack from the browser pane tests nothing: a synthetic Cmd+V does not reach the
  system clipboard and Slack ignores synthetic paste events. The script's read-back is the check,
  and the user's paste is the real test.
- The script needs macOS: `textutil` and `NSPasteboard`.
