// Counts how often Claude kept the CLAUDE.md rules that a pattern can check, in the main session transcripts of the
// last days and in the commits of the repositories those sessions worked in. Prints counts only, never the text.
// Usage: node test/rules/adherence.mjs [--days 7] [--json | --show], where --show also says where each slip is
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const option = (name, fallback) => { const i = process.argv.indexOf(name); return i > -1 ? process.argv[i + 1] : fallback }
const DAYS = Number(option('--days', 7))
const config = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
const to = Date.now()
const from = to - DAYS * 86400000

const RULES = [
  { key: 'dashes', name: 'No long dashes in replies', unit: 'replies' },
  { key: 'plain', name: 'Plain quotes, arrows and dots in replies', unit: 'replies' },
  { key: 'feedback', name: 'A Prompt feedback section after each typed prompt', unit: 'replies' },
  { key: 'wrap', name: 'Commit message lines within 72 columns', unit: 'commits' },
  { key: 'attribution', name: 'No Claude attribution in commits', unit: 'commits' },
]
const count = Object.fromEntries(RULES.map(r => [r.key, { kept: 0, total: 0 }]))
const slips = []
const tally = (key, kept, where) => { count[key].total++; if (kept) count[key].kept++; else slips.push(`${key}: ${where}`) }

const textOf = content => typeof content === 'string' ? content
  : Array.isArray(content) ? content.filter(c => c && c.type === 'text').map(c => c.text).join('\n') : ''
const prose = text => text.replace(/```[\s\S]*?(```|$)/g, '').replace(/`[^`\n]*`/g, '')
const LONG_DASH = /—|\s–\s/
const TYPOGRAPHIC = /[‘’“”«»‹›…←-⇿]/
const TRAILER = /^(Co-authored-by|Reviewed-by|Signed-off-by): /i

const transcripts = new Set()
for (const dir of fs.readdirSync(path.join(config, 'projects'), { withFileTypes: true })) {
  if (!dir.isDirectory()) continue
  const folder = path.join(config, 'projects', dir.name)
  for (const f of fs.readdirSync(folder)) {
    const file = path.join(folder, f)
    if (f.endsWith('.jsonl') && fs.statSync(file).mtimeMs >= from) transcripts.add(fs.realpathSync(file))
  }
}
// A transcript written to in the last minutes may still be in its last turn.
const RUNNING_MS = 10 * 60000

const cwds = new Set()
let sessions = 0
for (const file of transcripts) {
  const turns = []
  let turn = null
  let lastBox = []
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    let rec
    try { rec = JSON.parse(line) } catch { continue }
    if (!rec || rec.isSidechain) continue
    if (rec.type === 'user' && rec.origin && rec.origin.kind === 'human') {
      const prompt = textOf(rec.message && rec.message.content).trim()
      turn = { at: Date.parse(rec.timestamp), text: [], interrupted: false, cwd: rec.cwd, shell: prompt.startsWith('<bash-input>'),
        button: lastBox.some(a => String(a.message || a.label || '').trim() === prompt) }
      turns.push(turn)
      continue
    }
    if (!turn) continue
    if (rec.type === 'user' && textOf(rec.message && rec.message.content).includes('[Request interrupted by user')) turn.interrupted = true
    if (rec.type !== 'assistant') continue
    for (const c of (rec.message && rec.message.content) || []) {
      if (c.type === 'text') turn.text.push(c.text)
      if (c.type === 'tool_use' && c.name === 'mcp__ccd_turn__wrap_up') lastBox = (c.input && c.input.actions) || []
    }
  }
  if (to - fs.statSync(file).mtimeMs < RUNNING_MS) turns.pop()
  const counted = turns.filter(t => t.at >= from && !t.interrupted && !t.shell && t.text.length)
  if (counted.length) sessions++
  for (const t of counted) {
    const text = prose(t.text.join('\n'))
    const where = `${file} at ${new Date(t.at).toISOString()}`
    tally('dashes', !LONG_DASH.test(text), where)
    tally('plain', !TYPOGRAPHIC.test(text), where)
    if (!t.button) tally('feedback', /prompt feedback/i.test(t.text.join('\n')), where)
    if (t.cwd) cwds.add(t.cwd)
  }
}

const git = (dir, ...args) => {
  const r = spawnSync('git', ['-C', dir, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
  return r.status === 0 ? r.stdout : ''
}
const repos = new Set()
for (const cwd of cwds) {
  if (!fs.existsSync(cwd) || cwd.startsWith(config) || cwd.includes('scratch-workspaces')) continue
  const common = git(cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir').trim()
  if (common.endsWith('/.git')) repos.add(path.dirname(common))
}
const seen = new Set()
for (const repo of repos) {
  const email = git(repo, 'config', 'user.email').trim()
  if (!email) continue
  const log = git(repo, 'log', '--exclude=refs/stash', '--all', '--no-merges', '-F', `--author=${email}`, `--since=@${Math.floor(from / 1000)}`, '--format=%H%x1f%B%x1e')
  for (const entry of log.split('\x1e')) {
    const [hash, body] = entry.trim().split('\x1f')
    if (!hash || !body || seen.has(hash)) continue
    seen.add(hash)
    const where = `${repo} ${hash.slice(0, 7)}`
    tally('wrap', body.split('\n').every(l => l.length <= 72 || TRAILER.test(l) || !/\s/.test(l.replace(/^[>\s]+/, ''))), where)
    tally('attribution', !/co-authored-by:[^\n]*(claude|anthropic)|generated with \[?claude/i.test(body), where)
  }
}

const day = ms => new Date(ms).toISOString().slice(0, 10)
const result = { from: day(from), to: day(to), sessions, repos: repos.size, rules: RULES.map(r => ({ ...r, ...count[r.key] })) }
if (process.argv.includes('--json')) {
  console.log(JSON.stringify(result))
} else {
  console.log(`Rules kept from ${result.from} to ${result.to}, in ${sessions} sessions and the commits of ${repos.size} repositories:`)
  for (const r of result.rules) console.log(`  ${r.name}: ${r.kept} of ${r.total} ${r.unit}`)
  if (process.argv.includes('--show')) console.log(slips.join('\n'))
}
