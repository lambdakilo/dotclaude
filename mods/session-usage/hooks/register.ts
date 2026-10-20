import type { EngineInterface, Register } from 'claude-code'

type Usage = { figures: string; coldAt: number; offset: number }

const DAY = 86_400_000
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const FIRE = '\u{1F525}'
const ICE = '\u{1F9CA}'

let usage: Usage | undefined
let shown: string | undefined
let isBusy = false

const pad = (n: number) => String(n).padStart(2, '0')

// The offset is the one usage.sh read from the host's clock, so the UTC
// getters give local time whatever zone this environment runs in.
const cache = (now: number, { coldAt, offset }: Usage) => {
  const left = coldAt - now
  if (left >= 60_000) return `${FIRE} ${Math.floor(left / 60_000)} min`
  if (left > 0) return `${FIRE} <1 min`

  const cold = new Date(coldAt + offset)
  const isToday = Math.floor((coldAt + offset) / DAY) === Math.floor((now + offset) / DAY)

  return isToday
    ? `${ICE} since ${pad(cold.getUTCHours())}:${pad(cold.getUTCMinutes())}`
    : `${ICE} since ${cold.getUTCDate()} ${MONTHS[cold.getUTCMonth()]}`
}

const line = async ($: EngineInterface) => usage && `${cache(await $.clock.now(), usage)}, ${usage.figures}`

const show = async ($: EngineInterface) => {
  const id = await $.session.id()
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/usage.sh`, '--status', id])
  const [figures, coldAt, offset] = stdout.trim().split('\n')
  usage =
    exitCode === 0 && figures && coldAt && offset
      ? { figures, coldAt: Number(coldAt) * 1000, offset: Number(offset) * 1000 }
      : undefined

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
