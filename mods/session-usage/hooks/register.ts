import type { EngineInterface, Register } from 'claude-code'

const show = async ($: EngineInterface) => {
  const id = await $.session.id()
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/usage.sh`, id])
  const line = stdout.trim()

  $.ui.status(exitCode === 0 && line !== '' ? line : undefined)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await show($)

    return started
  })

  on('turn.complete', async ($, e, next) => {
    const completed = await next(e)
    if (e.agentId === undefined) await show($)

    return completed
  })
}
