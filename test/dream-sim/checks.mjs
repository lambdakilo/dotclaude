// Runs dream.js against the simulation in run.mjs and checks how each mode spends and stops.
// Usage: node test/dream-sim/checks.mjs [path to dream.js]
import { loadWorkflow, simulate } from './run.mjs'

const wf = await loadWorkflow(process.argv[2] || new URL('../../workflows/dream.js', import.meta.url).pathname)
const workAt = Date.parse('2026-10-17T05:00:00Z')
const reset = Date.parse('2026-10-17T13:59:59Z')
const noHits = ['no agent reaches a limit and fails', st => st.hits === 0]
const sat = { five: 8, fiveReset: '2026-10-17T10:00:00Z', weekReset: '2026-10-17T13:59:59Z', now: '2026-10-17T07:00:00Z', since: '2026-10-16T22:00:00Z' }
const fri = { five: 10, fiveReset: '2026-10-16T16:49:59Z', weekReset: '2026-10-17T13:59:59Z', now: '2026-10-16T15:10:00Z', since: '2026-10-14T00:00:00Z' }
const wed = { five: 5, fiveReset: '2026-10-14T21:00:00Z', weekReset: '2026-10-17T13:59:59Z', now: '2026-10-14T18:00:00Z', since: '2026-10-13T18:00:00Z' }

const scenarios = [
  ['eve, real numbers', { ...fri, week: 54, sessions: 48 }, [
    ['mode is eve', (st, r) => r.mode.startsWith('eve')],
    ['weekly stays under 95 minus the reserve, plus a point', st => st.maxWeek <= 95 - 2 * 16.9 + 1],
    ['no window the run touched is open at 08:00 Saturday', st => !st.windows.some(([a, b]) => a <= workAt && workAt < b && st.lastUse >= a)],
    noHits,
  ]],
  ['eve, big budget', { ...fri, week: 10, since: '2026-10-10T00:00:00Z', sessions: 400 }, [
    ['no window the run touched is open at 08:00 Saturday', st => !st.windows.some(([a, b]) => a <= workAt && workAt < b && st.lastUse >= a)],
    noHits,
  ]],
  ['final, little work', { ...sat, week: 64, sessions: 6 }, [
    ['mode is final', (st, r) => r.mode.startsWith('final')],
    ['nothing used after the weekly reset', st => st.afterWeekReset === 0],
    noHits,
  ]],
  ...[80, 88, 93, 97].map(week => [`final, weekly at ${week}`, { ...sat, week, sessions: 200 }, [
    ['weekly never passes 99.5', st => st.maxWeek <= 99.5],
    ['last use before the reset', st => st.lastUse < reset],
    noHits,
  ]]),
  ['final, stopped by the 5-hour window', { ...sat, week: 80, sessions: 200 }, [
    ['says when another run could spend the rest', (st, r) => /another \/dream after/.test(r.verification.stoppedBy)],
  ]],
  ['night', { ...wed, week: 30, sessions: 20 }, [
    ['mode is night', (st, r) => r.mode.startsWith('night')],
    ['no deep, subagents or brief', st => !st.labels.deep && !st.labels.subagents && !st.labels.monday],
    noHits,
  ]],
  ['night, weekly resets mid-run', { ...wed, week: 30, sessions: 120, weekJumpAt: '2026-10-14T19:00:00Z' }, [
    ['stops starting work after the reset', (st, r) => r.skipped > 0],
  ]],
  ['day', { ...wed, args: { mode: 'day' }, now: '2026-10-14T09:00:00Z', five: 60, fiveReset: '2026-10-14T12:00:00Z', week: 30, sessions: 40 }, [noHits]],
  ['usage unreadable', { ...wed, unreadable: true, week: 30, sessions: 8 }, [
    ['falls back to night', (st, r) => r.mode.startsWith('night')],
  ]],
  ['carried and parked backlog', { ...wed, week: 30, sessions: 4, backlog: {
    valid: true,
    open: [
      { key: 'parked', title: 'parked', kind: 'hook', impact: 'high', target: '~/x', firstSeen: '2026-10-10', lastSeen: '2026-10-10', scriptFile: '', askAgainAfter: '2026-10-20' },
      { key: 'due', title: 'due', kind: 'hook', impact: 'high', target: '~/y', firstSeen: '2026-10-10', lastSeen: '2026-10-10', scriptFile: '', askAgainAfter: '2026-10-12' },
    ],
    closed: [],
    unchecked: [{ key: 'old-n1', title: 'old one', kind: 'hook', impact: 'high', target: '~/z', firstSeen: '2026-10-10' }],
  } }, [
    ['the parked item stays out of the plan', (st, r) => !r.plan.some(p => p.includes('(parked)'))],
    ['the due item is in the plan', (st, r) => r.plan.some(p => p.includes('(due)'))],
    ['the carried unchecked one is checked by reading it from the backlog', st => /Read its whole text first with jq '\.unchecked\[\] \| select\(\.key == "old-n1"\)'/.test(st.prompts['fit old-n1'] || '')],
    ['the fit check asks for the exact change and both examples', st => /exactChange/.test(st.prompts['fit old-n1'] || '') && /exampleFixed/.test(st.prompts['fit old-n1'] || '')],
    ['the patch carries the examples', st => /"exampleWrong":"it broke"/.test(st.prompts['backlog patch'] || '') || Object.keys(st.prompts).some(k => k.startsWith('backlog items') && /"exampleWrong":"it broke"/.test(st.prompts[k]))],
    ['the session is told to ask one step at a time with the examples', (st, r) => /one AskUserQuestion call per step/.test(r.forTheSession) && /exampleWrong/.test(r.forTheSession)],
  ]],
  ['review of the open backlog', { ...wed, week: 30, sessions: 4, args: 'review', backlog: {
    valid: true,
    open: [
      { key: 'low-one', title: 'low', kind: 'hook', impact: 'low', target: '~/a', scriptFile: '~/.claude/dream/x/p9.sh' },
      { key: 'parked', title: 'parked', kind: 'hook', impact: 'high', target: '~/b', scriptFile: '', askAgainAfter: '2026-10-20' },
      { key: 'high-one', title: 'high', kind: 'hook', impact: 'high', target: '~/c', scriptFile: '~/.claude/dream/x/p2.sh' },
    ],
    closed: [],
    unchecked: [{ key: 'u1', title: 'u', kind: 'hook', impact: 'low', target: '~/d' }],
  } }, [
    ['runs one agent and nothing else', st => Object.keys(st.labels).join() === 'review'],
    ['asks about the due steps, high before low', (st, r) => r.due === 2 && r.forTheSession.indexOf('"high-one"') < r.forTheSession.indexOf('"low-one"')],
    ['leaves the parked step out', (st, r) => r.waiting === 1 && !r.forTheSession.includes('"parked"')],
    ['uses the same one-at-a-time dialogue', (st, r) => /^1 open proposals wait/.test(r.forTheSession) && /one AskUserQuestion call per step/.test(r.forTheSession)],
    ['tests a script in a sandbox before running it', (st, r) => /test it in a sandbox before running it for real/.test(r.forTheSession)],
    ['names the unchecked ones', (st, r) => /1 unchecked proposals wait/.test(r.forTheSession)],
  ]],
]

let failed = 0
for (const [name, sc, checks] of scenarios) {
  const { st, result } = await simulate(wf, sc)
  if (result.crash) { console.log(`CRASH ${name}\n${result.crash}`); failed++; continue }
  const lines = checks.map(([desc, ok]) => { const pass = Boolean(ok(st, result)); if (!pass) failed++; return `  ${pass ? 'PASS' : 'FAIL'}: ${desc}` })
  console.log(`== ${name}: weekly ${sc.week} to ${st.maxWeek.toFixed(1)}, agents failed at a limit ${st.hits}`)
  console.log(lines.join('\n'))
}
console.log(failed ? `${failed} checks failed` : 'all checks passed')
process.exit(failed ? 1 : 0)
