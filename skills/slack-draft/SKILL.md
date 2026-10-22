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
rich text, so every draft goes on the clipboard as rich text, plain ones too, and the user sends
it with one paste.

## Steps

1. Write the draft as an HTML fragment in `~/Downloads/<topic>.html`, with words separated by
   dashes, starting with `<meta charset="utf-8">`. Use only what Slack keeps from a paste: `<p>`,
   `<b>`, `<i>`, `<code>`, `<a href>`, `<ul>` or `<ol>` with `<li>`, `<blockquote>` and `<pre>`. A
   bold label opens each list item.
2. Link the evidence a claim rests on, pinned so the link still shows what the text says later:
   - a commit: `https://github.com/<owner>/<repo>/commit/<full sha>`, the short hash as code text
   - lines of a file: `https://github.com/<owner>/<repo>/blob/<full sha>/<path>#L<a>-L<b>`, with
     the sha of the commit that was read, never a branch name
   - a pull request or an issue: its full URL, never a bare `#123`
   - a Figma frame: `https://www.figma.com/design/<file key>/<slug>?node-id=<a>-<b>`
   - a Slack message: its permalink from the Slack connector

   Check each GitHub link with `gh api`, the `contents` endpoint with `?ref=<sha>` for a file and
   the `commits` endpoint for a commit. Never name a shell variable `path` in that loop: zsh ties
   it to `PATH`.
3. Run the copy script. It prints what it read back and exits non-zero when a type is missing.
   ```bash
   ~/.claude/skills/slack-draft/copy-rich.sh ~/Downloads/<topic>.html
   ```
4. In the reply, show the draft as a fenced `text` block so it can be read in the chat, say it is
   on the clipboard, and name each link the recipients may not be able to open, such as a private
   repository or a permalink from another workspace. Then the steps: paste with Cmd+V in Slack and
   check it before sending, and the command that puts it back on the clipboard once something else
   overwrote it, with the draft's own file name in place of `<topic>`:
   ```bash
   ~/.claude/skills/slack-draft/copy-rich.sh ~/Downloads/<topic>.html
   ```

## What does not work

- AppleScript's `set the clipboard to` with HTML data writes HTML alone, and most paste targets
  then find nothing.
- A paste into Slack from the browser pane tests nothing: a synthetic Cmd+V does not reach the
  system clipboard and Slack ignores synthetic paste events. The script's read-back is the check,
  and the user's paste is the real test.
- The script needs macOS: `textutil` and `NSPasteboard`.
