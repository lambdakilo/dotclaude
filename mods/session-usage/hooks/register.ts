import type { EngineInterface, Register } from 'claude-code'

type Usage = { figures: string; coldAt: number; clock: string }

let usage: Usage | undefined
let shown: string | undefined
let isBusy = false

const cache = (left: number, clock: string) => {
  if (left <= 0) return `cache cold since ${clock}`
  const minutes = Math.floor(left / 60_000)

  return `cache warm ${minutes < 1 ? '<1' : minutes} min, until ${clock}`
}

const line = async ($: EngineInterface) =>
  usage && `${usage.figures}, ${cache(usage.coldAt - (await $.clock.now()), usage.clock)}`

const show = async ($: EngineInterface) => {
  const id = await $.session.id()
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/usage.sh`, '--status', id])
  const [figures, coldAt, clock] = stdout.trim().split('\n')
  usage = exitCode === 0 && figures && coldAt && clock ? { figures, coldAt: Number(coldAt) * 1000, clock } : undefined

  shown = await line($)
  $.ui.status(shown)
}

// A running turn keeps refreshing the cache, so the transcript is read again.
const tick = async ($: EngineInterface) => {
  if (isBusy) return show($)
  const text = await line($)
  if (text === shown) return

  shown = text
  $.ui.status(text)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await show($)
    $.clock.every(15_000, () => void tick($))

    return started
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) isBusy = true

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const completed = await next(e)
    if (e.agentId === undefined) {
      isBusy = false
      await show($)
    }

    return completed
  })
}
