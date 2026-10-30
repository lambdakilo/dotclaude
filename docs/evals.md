# Evals

These are the numbers from the last `/dream` run, or from the last time I ran the evals by hand. The
rule counts come from my own sessions, and only the counts leave my computer. To run the evals on
your copy:

```bash
node ~/Projects/dotclaude/test/evals.mjs
```

<!-- evals:start -->
| Suite | What it checks | Result |
| --- | --- | --- |
| [Hook tests](../test/hooks/checks.mjs) | every hook, fed the input Claude Code sends it | 222 of 222 pass |
| [Dream simulation](../test/dream-sim/checks.mjs) | how `/dream` spends usage and when it stops | 53 of 53 pass |
| [Usage mod tests](../mods/session-usage/hooks/register.test.ts) | the line under the prompt box | 4 of 4 pass |

How often Claude kept rules from [`CLAUDE.md`](../CLAUDE.md) from 2026-10-23 to 2026-10-30, in 108 of my own sessions and the commits of the 10 repositories they worked in, counted by [`test/rules/adherence.mjs`](../test/rules/adherence.mjs):

| Rule | Kept |
| --- | --- |
| No long dashes in replies | 99% (488 of 490 replies) |
| Plain quotes, arrows and dots in replies | 99% (489 of 490 replies) |
| A Prompt feedback section after each typed prompt | 99% (428 of 431 replies) |
| Commit message lines within 72 columns | 99% (349 of 350 commits) |
| No Claude attribution in commits | 100% (350 of 350 commits) |
<!-- evals:end -->
