#!/usr/bin/env node

// Carries local files into a site open in the Claude Code app's built-in
// browser pane, which has no file upload tool and blocks other sites from
// calling localhost, and writes to disk what a page drawn in the pane posts.
// Start it with preview_start from this entry in .claude/launch.json, with the
// home directory spelled out, since nothing expands ~ there:
//
//   { "name": "pane-bridge", "runtimeExecutable": "node", "port": 8765,
//     "runtimeArgs": ["<home>/.claude/hooks/pane-bridge.mjs",
//       "--dir", "<folder>", "--back", "<site address>"] }
//
// The tab preview_start opens puts every file in the folder into window.name
// and goes on to the site, which keeps that name; /?back=<address> does the
// same from another tab. Then run what `pane-bridge.mjs site` prints with
// javascript_tool in that tab. It wraps HTMLInputElement.prototype.click, so
// the site's own upload button takes the files queued with
// __paneBridge.offer(<name>...) through a DataTransfer instead of opening the
// file picker. Click that button, then await __paneBridge.taken(), which
// returns an error rather than guess when no file input took them, such as on
// a site that only takes a drop.
//
// The other way round, a page under /f/ draws on a canvas and posts the blob
// to /save?name=<file>, which writes it into the folder. Without --back, /
// lists the folder. --port goes with a port other than 8765. The route rests
// on the pane keeping window.name from one site to the next, which Chromium
// may stop doing; the site script then says the name holds no files.

import fs from 'node:fs'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'

const site = String.raw`await (async () => {
  if (!window.name.startsWith('pane-bridge:')) {
    return { error: 'window.name holds no files: open the bridge page in this tab first' }
  }
  const list = JSON.parse(window.name.slice('pane-bridge:'.length))
  window.name = ''
  const bytes = (b64) => {
    const text = atob(b64)
    const out = new Uint8Array(text.length)
    for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i)
    return out
  }
  const bridge = (window.__paneBridge = {
    files: list.map(({ name, type, b64 }) => new File([bytes(b64)], name, { type })),
    queue: [],
  })
  bridge.offer = (...names) => {
    bridge.queue = names.map((name) => {
      const file = bridge.files.find((f) => f.name === name)
      if (!file) throw new Error('no file named ' + name)
      return file
    })
    return names
  }
  bridge.taken = async (ms = 3000) => {
    for (const end = Date.now() + ms; bridge.queue.length && Date.now() < end; ) {
      await new Promise((resolve) => setTimeout(resolve, 100))
    }
    if (!bridge.queue.length) return { taken: true }
    const left = bridge.queue.map((f) => f.name)
    bridge.queue = []
    return { error: 'no file input took these', left }
  }
  if (!window.__paneBridgeWrapped) {
    const wrap = (original) => function (...args) {
      const queue = window.__paneBridge?.queue
      if (this.type !== 'file' || !queue?.length) return original?.apply(this, args)
      const picked = new DataTransfer()
      for (const file of queue.splice(0, this.multiple ? queue.length : 1)) picked.items.add(file)
      this.files = picked.files
      this.dispatchEvent(new Event('input', { bubbles: true }))
      this.dispatchEvent(new Event('change', { bubbles: true }))
    }
    HTMLInputElement.prototype.click = wrap(HTMLInputElement.prototype.click)
    HTMLInputElement.prototype.showPicker = wrap(HTMLInputElement.prototype.showPicker)
    window.__paneBridgeWrapped = true
  }
  return bridge.files.map((f) => f.name + ' ' + f.size)
})()`

if (process.argv[2] === 'site') {
  console.log(site)
  process.exit(0)
}

const option = (flag) => {
  const at = process.argv.indexOf(flag)
  return at > 1 ? process.argv[at + 1] : undefined
}
const given = option('--dir')
if (!given) {
  console.error('usage: pane-bridge.mjs --dir <folder> [--back <site address>] [--port <n>] | site')
  process.exit(64)
}
const dir = path.resolve(given.replace(/^~(?=\/|$)/, os.homedir()))
const port = Number(option('--port') || 8765)
const own = ['localhost', '127.0.0.1', '[::1]'].map((host) => `http://${host}:${port}`)

const types = {
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp',
  svg: 'image/svg+xml', pdf: 'application/pdf', mp4: 'video/mp4', webm: 'video/webm',
  mov: 'video/quicktime', html: 'text/html', txt: 'text/plain', json: 'application/json',
}
const typeOf = (name) =>
  types[path.extname(name).slice(1).toLowerCase()] || 'application/octet-stream'
const plain = (name) => Boolean(name) && name === path.basename(name) && !name.startsWith('.')
const names = () => fs.readdirSync(dir)
  .filter((name) => plain(name) && fs.statSync(path.join(dir, name)).isFile()).sort()
const inScript = (value) => JSON.stringify(value).replace(/</g, '\\u003c')
const html = (text) => text.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`)

function page(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' })
  res.end(`<!doctype html><meta charset="utf-8"><title>pane-bridge</title>${body}`)
}

function handoff(res, to) {
  let target
  try {
    target = new URL(to)
  } catch {
    return page(res, 400, `<p>Not an address: ${html(to)}</p>`)
  }
  if (!/^https?:$/.test(target.protocol)) return page(res, 400, '<p>Only http and https.</p>')
  const files = names().map((name) => ({
    name, type: typeOf(name), b64: fs.readFileSync(path.join(dir, name)).toString('base64'),
  }))
  page(res, 200, `<p>Handing ${files.length} files to ${html(target.href)}</p><script>
window.name = ${inScript('pane-bridge:' + JSON.stringify(files))}
location.replace(${inScript(target.href)})
</script>`)
}

function save(req, res, name) {
  if (req.headers.origin && !own.includes(req.headers.origin)) {
    res.writeHead(403)
    return res.end('only a page on this server may save')
  }
  if (!plain(name)) {
    res.writeHead(400)
    return res.end('name must be a plain file name')
  }
  const chunks = []
  req.on('data', (chunk) => chunks.push(chunk))
  req.on('end', () => {
    const file = path.join(dir, name)
    fs.writeFileSync(file, Buffer.concat(chunks))
    res.writeHead(200, { 'Content-Type': 'text/plain' })
    res.end(`saved ${file}`)
  })
}

function handle(req, res) {
  const url = new URL(req.url, `http://localhost:${port}`)
  if (req.method === 'POST' && url.pathname === '/save') {
    return save(req, res, url.searchParams.get('name'))
  }
  if (req.method !== 'GET') {
    res.writeHead(405)
    return res.end()
  }
  if (url.pathname === '/') {
    const to = url.searchParams.get('back') || option('--back')
    if (to) return handoff(res, to)
    const list = names().map((n) => `<li><a href="/f/${encodeURIComponent(n)}">${html(n)}</a></li>`)
    return page(res, 200, `<p>${html(dir)}</p><ul>${list.join('')}</ul>`)
  }
  let name = ''
  try {
    if (url.pathname.startsWith('/f/')) name = decodeURIComponent(url.pathname.slice(3))
  } catch {}
  if (plain(name) && names().includes(name)) {
    const type = typeOf(name) + (typeOf(name).startsWith('text/') ? '; charset=utf-8' : '')
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' })
    return fs.createReadStream(path.join(dir, name)).pipe(res)
  }
  res.writeHead(404)
  res.end('not found')
}

if (!fs.statSync(dir, { throwIfNoEntry: false })?.isDirectory()) {
  console.error(`pane-bridge: no such folder: ${dir}`)
  process.exit(1)
}
for (const host of ['127.0.0.1', '::1']) {
  http.createServer(handle)
    .on('error', (error) => {
      if (host === '127.0.0.1') throw error
    })
    .listen(port, host)
}
console.log(`pane-bridge serving ${dir} on port ${port}`)
