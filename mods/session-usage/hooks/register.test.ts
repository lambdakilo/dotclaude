import { expect, test } from 'claude-code/testing'

const TURN = { answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' } as const

const ran = (stdout: string) => ({
  value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

test('pins the script line after a main turn', async ($, on) => {
  const shown: (string | undefined)[] = []
  const argvs: string[][] = []
  on('session.id', () => ({ value: 'abc' }))
  on('process.run', ($, e) => {
    argvs.push([...e.argv])
    return ran('15% context, 4.3M tokens, $2.27, cache until 08:50\n')
  })
  on('ui.status', ($, e) => {
    shown.push(e.text)
    return { value: undefined }
  })
  on('turn.complete', () => ({ text: '' }))

  await $.turn.complete(TURN)

  expect(argvs).toHaveLength(1)
  expect(argvs[0]?.[0]).toMatch(/\/usage\.sh$/)
  expect(argvs[0]?.[1]).toBe('abc')
  expect(shown).toEqual(['15% context, 4.3M tokens, $2.27, cache until 08:50'])
})

test('leaves a subagent turn alone and clears on no line', async ($, on) => {
  const shown: (string | undefined)[] = []
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
