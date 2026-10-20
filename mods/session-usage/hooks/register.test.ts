import { expect, mock, test } from 'claude-code/testing'

const TURN = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const
const START = { cwd: '/', surface: 'terminal', isInteractive: true } as const
const FIGURES = '15% context, 4.3M tokens, $2.27, ~0.070 kWh, ~32 g CO2e'
const NOW = 1792488000_000

const ran = (stdout: string) => ({
  value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const warmFor = (minutes: number) => ran(`${FIGURES}\n${NOW / 1000 + minutes * 60}\n20 Oct 14:35\n`)

test('pins the figures and the cache countdown after a main turn', async ($, on) => {
  const shown: (string | undefined)[] = []
  const argvs: string[][] = []
  mock.clock(on, { now: NOW })
  on('session.id', () => ({ value: 'abc' }))
  on('process.run', ($, e) => {
    argvs.push([...e.argv])
    return warmFor(15)
  })
  on('ui.status', ($, e) => {
    shown.push(e.text)
    return { value: undefined }
  })
  on('turn.complete', () => ({ text: '' }))

  await $.turn.complete(TURN)

  expect(argvs).toHaveLength(1)
  expect(argvs[0]?.[0]).toMatch(/\/usage\.sh$/)
  expect(argvs[0]?.slice(1)).toEqual(['--status', 'abc'])
  expect(shown).toEqual([`${FIGURES}, cache warm 15 min, until 20 Oct 14:35`])
})

test('counts the minutes down between turns without reading the transcript again', async ($, on) => {
  const shown: (string | undefined)[] = []
  let runs = 0
  const clock = mock.clock(on, { now: NOW })
  on('session.id', () => ({ value: 'abc' }))
  on('process.run', () => {
    runs++
    return warmFor(2)
  })
  on('ui.status', ($, e) => {
    shown.push(e.text)
    return { value: undefined }
  })
  on('session.start', () => ({ cwd: '/' }))

  await $.session.start(START)
  await clock.advance(60_000)
  await clock.advance(45_000)
  await clock.advance(15_000)
  await clock.advance(60_000)

  expect(runs).toBe(1)
  expect(shown).toEqual([
    `${FIGURES}, cache warm 2 min, until 20 Oct 14:35`,
    `${FIGURES}, cache warm 1 min, until 20 Oct 14:35`,
    `${FIGURES}, cache warm <1 min, until 20 Oct 14:35`,
    `${FIGURES}, cache cold since 20 Oct 14:35`,
  ])
})

test('reads the transcript on each tick while a main turn runs', async ($, on) => {
  let runs = 0
  const clock = mock.clock(on, { now: NOW })
  on('session.id', () => ({ value: 'abc' }))
  on('process.run', () => {
    runs++
    return warmFor(60)
  })
  on('ui.status', () => ({ value: undefined }))
  on('session.start', () => ({ cwd: '/' }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))

  await $.session.start(START)
  await $.turn.start({ text: 'go', turnId: 't1', agentId: 'sub' })
  await clock.advance(15_000)
  expect(runs).toBe(1)

  await $.turn.start({ text: 'go', turnId: 't1' })
  await clock.advance(30_000)
  expect(runs).toBe(3)

  await $.turn.complete(TURN)
  await clock.advance(30_000)
  expect(runs).toBe(4)
})

test('leaves a subagent turn alone and clears on no line', async ($, on) => {
  const shown: (string | undefined)[] = []
  mock.clock(on, { now: NOW })
  on('session.id', () => ({ value: 'abc' }))
  on('process.run', () => ran(''))
  on('ui.status', ($, e) => {
    shown.push(e.text)
    return { value: undefined }
  })
  on('turn.complete', () => ({ text: '' }))

  await $.turn.complete({ ...TURN, agentId: 'sub' })
  expect(shown).toEqual([])

  await $.turn.complete(TURN)
  expect(shown).toEqual([undefined])
})
