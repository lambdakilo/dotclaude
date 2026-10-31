import type { EngineInterface, Register } from 'claude-code'

type Usage = { figures: string; coldAt: number; offset: number }
type Other = { coldAt: number; title: string }

const DAY = 86_400_000
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const FIRE = '\u{1F525}'
const ICE = '\u{1F9CA}'
const HOURGLASS = '\u23F3'
// The desktop app cuts the status line at about this many characters.
const WIDTH = 40

// An emoji takes two columns, the hourglass too, though it is one UTF-16 unit.
const width = (text: string) => [...text].reduce((n, c) => n + ((c.codePointAt(0) ?? 0) >= 0x2300 ? 2 : 1), 0)

let usage: Usage | undefined
let others: Other[] = []
let othersReadAt = -Infinity
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

const fit = (title: string, room: number) => {
  if (title.length <= room) return title
  const space = title.lastIndexOf(' ', room)

  return title.slice(0, space > 0 ? space : room).replace(/[\s,:;+-]+$/, '')
}

// The other session that goes cold next, its title cut at a word to fit.
const next = (now: number, room: number) => {
  const other = others.find(o => o.coldAt > now)
  if (!other) return ''

  const left = other.coldAt - now
  const head = `, ${HOURGLASS} ${left >= 60_000 ? Math.floor(left / 60_000) : '<1'}m `
  const title = fit(other.title, room - width(head))

  return title ? head + title : ''
}

const line = async ($: EngineInterface) => {
  if (!usage) return undefined
  const now = await $.clock.now()
  const own = `${cache(now, usage)}, ${usage.figures}`

  return own + next(now, WIDTH - width(own))
}

const readOthers = async ($: EngineInterface) => {
  const id = await $.session.id()
  const { exitCode, stdout } = await $.process.run([`${$.plugin.root}/usage.sh`, '--next', id])
  others =
    exitCode === 0
      ? stdout
          .split('\n')
          .filter(Boolean)
          .map(row => {
            const [coldAt = '', title = ''] = row.split('\t')
            return { coldAt: Number(coldAt) * 1000, title }
          })
      : []
  othersReadAt = await $.clock.now()
}

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
// The other sessions are read once a minute, which also drops one archived.
const tick = async ($: EngineInterface) => {
  if ((await $.clock.now()) - othersReadAt >= 60_000) await readOthers($)
  if (isBusy) return show($)
  const text = await line($)
  if (text === shown) return

  shown = text
  $.ui.status(text)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await readOthers($)
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
