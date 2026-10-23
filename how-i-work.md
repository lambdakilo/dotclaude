# How I work

This is how I use the setup in this repository from day to day, on a MacBook Air with an M5 chip.
It leaves out what I work on.

## Start of day

Each morning, before I start anything, I run `sod`, short for start of day, in a terminal:

```zsh
sod
```

It lives at `~/bin/sod`, and `~/bin` is on my `PATH`:

```zsh
#!/bin/zsh
set -euo pipefail

if docker info >/dev/null 2>&1; then
  docker ps -q | xargs docker stop
  docker container prune -f
  docker volume prune -af
fi

brew update
brew upgrade -y
brew cleanup
```

If Docker is running, it stops every container and deletes the containers and all their volumes,
so each project starts the day from fresh test data and nothing from yesterday keeps running.
Anything I changed by hand in a local database is gone. Then it updates Homebrew and everything
Homebrew installed, without asking, and removes the old versions.

## Prompting

I work in the Code tab of the Claude desktop app, one session per task, started in the project's
folder under `~/Projects`. Sessions run in auto mode, so Claude does not ask before every command,
and [`settings.json`](settings.json) picks the model and the effort.

I write prompts the way I would message a colleague: short, lowercase, typos left in. "start doing
issue 123" or "review pr 123" is a whole prompt. Claude reads the issue, the code and its notes,
and asks me only what is mine to decide, as a question with its recommended answer first. Most of
my follow-ups are a word or a click: "go", "shorter", "commit and push", or a button in the box
Claude leaves at the end of its turn. A follow-up that is a task of its own, Claude offers as a
new session I can start with one click.

Two habits do most of the work:

- When Claude does something that should never happen again, I put `dotclaude` in the prompt, as
  in "dotclaude fix. next time ...". Claude writes the rule into [`CLAUDE.md`](CLAUDE.md) or a
  skill, runs [`sync.sh`](sync.sh), and commits and pushes it here with my prompt quoted. Many of
  the rules here started that way.
- Every reply ends with a short Prompt feedback section: what my prompt left out, and a rewrite.
  I read it and write the next prompt better.

## Browsers

Firefox is my default browser, so the links Claude gives me, such as a pull request or a page it
made, open there. Claude does its own browsing in the browser built into the desktop app, the pane
beside the chat, where I sign in once to the sites it needs. Claude in Chrome is blocked in
`settings.json`, so Claude never drives a browser I am using.

## Battery and sleep

The Air spends nights on its charger while Claude works, so it never charges past 80%. I set this
once:

1. Open System Settings and click Battery in the sidebar.
2. Click the info button next to Charging, set Charge Limit to 80%, and click Done.

Charge Limit needs macOS Tahoe 26.4 or later and a Mac with Apple silicon, as
[Apple's support page](https://support.apple.com/102338) says.

Nothing may put the Mac to sleep while Claude works. In the Claude app, Settings > Claude Code has
"Keep computer awake while Claude works" and "Keep awake on battery power", and both are on. macOS
itself never sleeps on a timer:

```zsh
sudo pmset -a sleep 0 disksleep 0
```

The display still turns off after 3 minutes:

```zsh
sudo pmset -a displaysleep 3
```

I also veto sleep altogether, so a long run is never cut short. The cost is that the Air stays
awake on battery too, until I shut it down:

```zsh
sudo pmset -a disablesleep 1
```

This shows what is in effect:

```zsh
pmset -g
```

## Dreaming at the weekend

The weekly limit of my Claude plan resets on Saturday afternoon. [`/dream`](workflows/dream.js)
reads the reset time from the usage card in the app and picks its mode by itself, so I run it
twice around the reset:

1. Friday, when I get home: connect the charger, leave the Claude app open, and send this in a new
   Code session.

   ```text
   /dream
   ```

   On the day before the reset this is an eve run. It spends most of what is left of the week
   overnight, but keeps back two 5-hour windows, one for my work on Saturday and one for the
   final run, and leaves the 5-hour window that would be open at 08:00 on Saturday untouched.

2. Saturday: open that session. It goes through what it proposes one question at a time, each
   with the exact change, a moment where things went wrong and how that moment goes once the
   change is in. I answer "Add it" or "Not now", and Claude applies what I added and pushes it
   here. Then I carry on with my own work.

3. Saturday, when I am done: connect the charger again and send `/dream` in a new Code session.
   On the reset day this is a final run. It spends the rest of the week, down to 1 percentage
   point, and stops starting work an hour and a quarter before the reset, so everything reports
   back in time.

4. The next time I sit down: open that session and go through its proposals the same way.
