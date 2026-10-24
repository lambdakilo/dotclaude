// Feeds each hook in hooks/ the JSON Claude Code would send it, inside a throwaway home folder, and checks what it does.
// Usage: node test/hooks/checks.mjs [path to hooks/]
import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const ROOT = new URL('../..', import.meta.url).pathname
const HOOKS = path.resolve(process.argv[2] || path.join(ROOT, 'hooks'))
const USAGE_SH = path.join(ROOT, 'mods/session-usage/usage.sh')
const home = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'hook-checks-')))
const config = path.join(home, '.claude')
// Addresses and home paths are put together at run time, so the sync.sh scan does not take them for real ones.
const address = (name, domain = 'example.com') => [name, domain].join('@')
const otherHome = ['', 'Users', 'someone'].join('/')
const ENV = { PATH: process.env.PATH, HOME: home, CLAUDE_CONFIG_DIR: config, TMPDIR: path.join(home, 'tmp'), LANG: 'en_US.UTF-8', GIT_CONFIG_NOSYSTEM: '1' }

const write = (file, text) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); return file }
const jsonl = (file, records) => write(file, records.map(r => JSON.stringify(r)).join('\n') + '\n')
const q = s => `'${s.replace(/'/g, `'\\''`)}'`
const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
fs.mkdirSync(ENV.TMPDIR, { recursive: true })
write(path.join(home, '.gitconfig'), `[user]\n\tname = Test\n\temail = ${address('test')}\n[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n[commit]\n\tgpgsign = false\n`)

function sh(cmd, cwd = home) {
  const r = spawnSync('bash', ['-c', cmd], { cwd, env: ENV, encoding: 'utf8' })
  if (r.status !== 0) throw new Error(`setup failed: ${cmd}\n${r.stderr}`)
  return r.stdout
}
function run(hook, input, { args = [], env = {}, cwd = home } = {}) {
  const r = spawnSync('bash', [path.join(HOOKS, hook), ...args], {
    cwd, env: { ...ENV, ...env }, encoding: 'utf8', timeout: 30000,
    input: typeof input === 'string' ? input : JSON.stringify(input),
  })
  return { code: r.status, out: r.stdout, err: r.stderr }
}
const quiet = r => r.code === 0 && r.out === '' && r.err === ''
const refused = r => r.code === 2 && r.err !== ''
const output = r => { try { return JSON.parse(r.out) } catch { return {} } }
const decision = r => output(r).hookSpecificOutput?.permissionDecision || ''
const context = r => output(r).hookSpecificOutput?.additionalContext || ''
const bash = (command, cwd = home) => ({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command }, cwd, session_id: 's1' })
const human = content => ({ type: 'user', origin: { kind: 'human' }, message: { role: 'user', content } })
const says = text => ({ type: 'assistant', message: { content: [{ type: 'text', text }] } })
const uses = (name, input) => ({ type: 'assistant', message: { content: [{ type: 'tool_use', name, input }] } })
const toolResult = content => ({ type: 'user', message: { content: [{ type: 'tool_result', content }] } })

const suites = [
  ['calendar-free-busy-only.sh', run => [
    ['lets the user\'s own calendar through', () => quiet(run({ tool_input: { calendarId: 'primary' } }))],
    ['lets a shared group calendar through', () => quiet(run({ tool_input: { calendarId: address('team', 'group.calendar.google.com') } }))],
    ['denies another person\'s calendar', () => decision(run({ tool_input: { calendarId: address('someone') } })) === 'deny'],
  ]],

  ['check-not-piped.sh', run => [
    ['refuses a test run piped into tail', () => refused(run(bash('npm test | tail -5')))],
    ['refuses vitest piped into grep', () => refused(run(bash('npx vitest run 2>&1 | grep FAIL')))],
    ['refuses make test piped after a cd', () => refused(run(bash('cd app && make test | tee log')))],
    ['lets it through with pipefail set', () => quiet(run(bash('set -o pipefail; npm test | tail -5')))],
    ['lets output sent to a file through', () => quiet(run(bash('npm test > /tmp/test.log 2>&1; echo exit=$?')))],
    ['ignores the words inside quotes', () => quiet(run(bash("echo 'npm test | tail'")))],
    ['ignores a pipe that holds no check', () => quiet(run(bash('git log --oneline | head')))],
  ]],

  ['no-github-posts.sh', run => [
    ['refuses gh pr comment', () => refused(run(bash('gh pr comment 12 --body hi')))],
    ['refuses gh issue comment', () => refused(run(bash('gh issue comment 3 -b hi')))],
    ['refuses gh pr review', () => refused(run(bash('gh pr review 12 --approve')))],
    ['refuses a close with a comment', () => refused(run(bash('gh issue close 3 --comment done')))],
    ['lets a close without a comment through', () => quiet(run(bash('gh issue close 3')))],
    ['refuses a gh api post to a comments path', () => refused(run(bash('gh api repos/o/r/issues/3/comments -f body=hi')))],
    ['lets a gh api read of comments with -X GET through', () => quiet(run(bash('gh api -X GET repos/o/r/pulls/3/comments -f per_page=100')))],
    ['refuses a GraphQL mutation that resolves a thread', () => refused(run(bash(`gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "x"}) { thread { id } } }'`)))],
    ['lets reading a PR through', () => quiet(run(bash('gh pr view 12 --comments')))],
    ['ignores a gh command named in a grep', () => quiet(run(bash("grep 'gh pr comment' notes.md")))],
    ['lets a PR body edit through', () => quiet(run(bash('gh pr edit 12 --body-file body.md')))],
  ]],

  ['no-home-search.sh', run => [
    ['refuses find in the home folder', () => refused(run(bash('find ~ -name x')))],
    ['refuses find in $HOME', () => refused(run(bash('find "$HOME" -name x')))],
    ['refuses grep -r from the root', () => refused(run(bash('grep -r secret /')))],
    ['refuses mdfind without -onlyin', () => refused(run(bash('mdfind kMDItemDisplayName=x')))],
    ['refuses find . after a cd to the home folder', () => refused(run(bash('cd ~ && find . -name x', path.join(home, 'Projects'))))],
    ['refuses find . run from the home folder', () => refused(run(bash('find . -name x')))],
    ['refuses another user\'s home folder', () => refused(run(bash(`du -sh ${otherHome}`)))],
    ['lets mdfind -onlyin through', () => quiet(run(bash('mdfind -onlyin ~/Projects x')))],
    ['lets find in a project folder through', () => quiet(run(bash('find ~/Projects/app -name x')))],
    ['lets find . in a project folder through', () => quiet(run(bash('find . -name x', path.join(home, 'Projects'))))],
    ['lets a plain grep of one file through', () => quiet(run(bash('grep secret /etc/hosts')))],
  ]],

  ['cd-fall-through.sh', run => [
    ['refuses a part after ; when the cd can fail', () => refused(run(bash('cd /nonexistent-dir; rm -rf build')))],
    ['refuses it on the next line too', () => refused(run(bash('cd /nonexistent-dir\nmake clean')))],
    ['refuses it inside a subshell', () => refused(run(bash('(cd /nonexistent-dir; ls)')))],
    ['resolves a variable set in the command', () => refused(run(bash('D=/nonexistent-dir; cd $D; ls')))],
    ['lets && after the cd through', () => quiet(run(bash('(cd /nonexistent-dir && ls)')))],
    ['lets a cd guarded with || exit through', () => quiet(run(bash('cd /nonexistent-dir || exit 1; ls')))],
    ['lets a cd after set -e through', () => quiet(run(bash('set -e; cd /nonexistent-dir; ls')))],
    ['lets a cd into a folder that exists through', () => quiet(run(bash('cd /tmp; ls')))],
    ['lets a cd with nothing after it through', () => quiet(run(bash('cd /nonexistent-dir')))],
    ['ignores a cd inside quotes', () => quiet(run(bash("echo 'cd /nonexistent-dir; ls'")))],
  ]],

  ['no-git-checkout.sh', run => [
    ['refuses a branch change with git checkout', () => refused(run(bash('git checkout main')))],
    ['refuses a file restore with git checkout', () => refused(run(bash('git checkout HEAD~1 -- src/a.ts')))],
    ['names git restore --source for a file from a commit', () => run(bash('git checkout HEAD~1 -- src/a.ts')).err.includes('git restore --source')],
    ['lets gh pr checkout through', () => quiet(run(bash('gh pr checkout 12')))],
    ['lets git switch through', () => quiet(run(bash('git switch main')))],
    ['ignores the word in an echo', () => quiet(run(bash('echo git checkout is old')))],
  ]],

  ['claude-md-changed.sh', run => {
    const rules = path.join(config, 'CLAUDE.md')
    const event = (hook_event_name, extra = {}) => ({ hook_event_name, session_id: 'md1', transcript_path: '', ...extra })
    const commit = event('PreToolUse', { tool_input: { command: 'git commit -F msg.txt' } })
    const skill = path.join(config, 'skills/pull-requests/SKILL.md')
    const prEdit = event('PreToolUse', { session_id: 'md2', tool_input: { command: 'gh pr edit 7 --body-file body.md' } })
    return [
      ['takes a copy at session start and says nothing', () => { write(rules, '- one\n'); return quiet(run(event('SessionStart'))) }],
      ['adds nothing to a prompt while the file is unchanged', () => quiet(run(event('UserPromptSubmit')))],
      ['adds the diff to the next prompt after an edit, with nothing on stderr', () => {
        write(rules, '- one\n- two\n')
        const r = run(event('UserPromptSubmit'))
        return r.code === 0 && context(r).includes('+- two') && r.err === ''
      }],
      ['adds that diff only once', () => quiet(run(event('UserPromptSubmit')))],
      ['lets other commands through after an edit', () => { write(rules, '- one\n- two\n- three\n'); return quiet(run(event('PreToolUse', { tool_input: { command: 'ls' } }))) }],
      ['blocks the next commit once with the diff', () => { const r = run(commit); return refused(r) && r.err.includes('+- three') }],
      ['then lets the commit through', () => quiet(run(commit))],
      ['takes a subagent\'s first look as its copy', () => quiet(run({ ...commit, agent_id: 'a1' }))],
      ['takes a copy of the pull-requests skill at session start', () => { write(skill, '- body\n'); return quiet(run(event('SessionStart', { session_id: 'md2' }))) }],
      ['lets a commit through after an edit of the skill alone', () => { write(skill, '- body\n- pictures\n'); return quiet(run({ ...commit, session_id: 'md2' })) }],
      ['blocks the next gh pr edit once with the skill diff', () => { const r = run(prEdit); return refused(r) && r.err.includes('SKILL.md changed') && r.err.includes('+- pictures') }],
      ['then lets gh pr edit through', () => quiet(run(prEdit))],
      ['adds the next edit of the skill to the next prompt', () => {
        write(skill, '- body\n- pictures\n- verify\n')
        const r = run(event('UserPromptSubmit', { session_id: 'md2' }))
        return r.code === 0 && context(r).includes('+- verify') && r.err === ''
      }],
      ['takes the session\'s own Edit of CLAUDE.md as seen', () => {
        const edit = event('PreToolUse', { session_id: 'md3', tool_name: 'Edit', tool_use_id: 'toolu_1', tool_input: { file_path: rules } })
        write(rules, '- one\n'); run(event('SessionStart', { session_id: 'md3' }))
        const pre = run(edit)
        write(rules, '- one\n- own\n')
        return quiet(pre) && quiet(run({ ...edit, hook_event_name: 'PostToolUse' })) && quiet(run({ ...commit, session_id: 'md3' }))
      }],
      ['still blocks for a peer\'s edit made before the session\'s own', () => {
        const edit = event('PreToolUse', { session_id: 'md3', tool_name: 'Edit', tool_use_id: 'toolu_2', tool_input: { file_path: rules } })
        write(rules, '- one\n- own\n- peer\n')
        run(edit); write(rules, '- one\n- own\n- peer\n- own again\n'); run({ ...edit, hook_event_name: 'PostToolUse' })
        const r = run({ ...commit, session_id: 'md3' })
        return refused(r) && r.err.includes('+- peer')
      }],
      ['takes a quick Bash call that changed the file as the session\'s own', () => {
        const fix = event('PreToolUse', { session_id: 'md3', tool_name: 'Bash', tool_use_id: 'toolu_3', tool_input: { command: 'bash fix.sh' } })
        run(fix); write(rules, '- fixed\n'); run({ ...fix, hook_event_name: 'PostToolUse' })
        return quiet(run({ ...commit, session_id: 'md3' }))
      }],
      ['still blocks when a sync.sh run changed the file', () => {
        const sync = event('PreToolUse', { session_id: 'md3', tool_name: 'Bash', tool_use_id: 'toolu_4', tool_input: { command: '~/Projects/dotclaude/sync.sh' } })
        run(sync); write(rules, '- pulled\n'); run({ ...sync, hook_event_name: 'PostToolUse' })
        const r = run({ ...commit, session_id: 'md3' })
        return refused(r) && r.err.includes('+- pulled')
      }],
      ['still blocks when the Bash call that changed the file took over a minute', () => {
        const slow = event('PreToolUse', { session_id: 'md3', tool_name: 'Bash', tool_use_id: 'toolu_5', tool_input: { command: 'npm test' } })
        run(slow); write(path.join(ENV.TMPDIR, 'claude-md-snapshots/md3.pre.toolu_5'), '0\n')
        write(rules, '- slow\n'); run({ ...slow, hook_event_name: 'PostToolUse' })
        const r = run({ ...commit, session_id: 'md3' })
        return refused(r) && r.err.includes('+- slow')
      }],
      ['takes the session\'s own Edit of the skill as seen', () => {
        const edit = event('PreToolUse', { session_id: 'md3', tool_name: 'Edit', tool_use_id: 'toolu_6', tool_input: { file_path: skill } })
        run(edit); write(skill, '- body\n- own\n'); run({ ...edit, hook_event_name: 'PostToolUse' })
        return quiet(run({ ...prEdit, session_id: 'md3' }))
      }],
      ['still blocks for a peer\'s CLAUDE.md edit made while the session edits the skill', () => {
        const edit = event('PreToolUse', { session_id: 'md3', tool_name: 'Edit', tool_use_id: 'toolu_7', tool_input: { file_path: skill } })
        run(edit); write(rules, '- peer again\n'); write(skill, '- body\n- own\n- more\n'); run({ ...edit, hook_event_name: 'PostToolUse' })
        const r = run({ ...commit, session_id: 'md3' })
        return refused(r) && r.err.includes('+- peer again') && !r.err.includes('SKILL.md')
      }],
    ]
  }],

  ['claude-md-memory-index.sh', run => {
    const rules = path.join(config, 'CLAUDE.md'), index = path.join(config, 'projects/-mi/memory/MEMORY.md')
    const edit = (file_path, session_id) => ({ hook_event_name: 'PostToolUse', tool_name: 'Edit', tool_input: { file_path }, session_id })
    const listed = r => r.err.split('the build runs with make').length - 1
    return [
      ['lists every memory index after an edit of CLAUDE.md', () => {
        write(rules, '- one\n')
        write(index, '- [Build](build.md): the build runs with make\n')
        const r = run(edit(rules, 'mi1'))
        return r.code === 2 && listed(r) === 1
      }],
      ['says it once in five minutes per session', () => quiet(run(edit(rules, 'mi1')))],
      ['leaves an edit of another file alone', () => quiet(run(edit(path.join(home, 'notes.md'), 'mi2')))],
      ['lists a symlinked project folder once', () => {
        fs.symlinkSync('-mi', path.join(config, 'projects/-mi-old'))
        return listed(run(edit(rules, 'mi3'))) === 1
      }],
    ]
  }],

  ['git-fetch-prune.sh', run => {
    const origin = path.join(home, 'fetch-origin.git'), other = path.join(home, 'fetch-other'), work = path.join(home, 'fetch-work')
    const env = { CLAUDE_PROJECT_DIR: work }
    const remoteBranches = () => sh(`git -C ${q(work)} branch -r`)
    return [
      ['fetches a new remote branch and prints nothing', () => {
        sh(`git init -q --bare ${q(origin)} && git clone -q ${q(origin)} ${q(other)} 2>/dev/null && git -C ${q(other)} commit -q --allow-empty -m one && git -C ${q(other)} push -q origin main && git clone -q ${q(origin)} ${q(work)} && git -C ${q(other)} push -q origin main:feature`)
        return quiet(run({}, { env })) && remoteBranches().includes('origin/feature')
      }],
      ['waits out the interval before fetching again', () => {
        sh(`git -C ${q(other)} push -q origin main:later`)
        return quiet(run({}, { env })) && !remoteBranches().includes('origin/later')
      }],
      ['does nothing outside a repository', () => quiet(run({}, { env: { CLAUDE_PROJECT_DIR: path.join(home, 'tmp') } }))],
    ]
  }],

  ['git-fetch-before-remote-base.sh', run => {
    const origin = path.join(home, 'base-origin.git'), other = path.join(home, 'base-other'), work = path.join(home, 'base-work')
    const remoteBranches = () => sh(`git -C ${q(work)} branch -r`)
    return [
      ['fetches before a rebase onto an origin ref', () => {
        sh(`git init -q --bare ${q(origin)} && git clone -q ${q(origin)} ${q(other)} 2>/dev/null && git -C ${q(other)} commit -q --allow-empty -m one && git -C ${q(other)} push -q origin main && git clone -q ${q(origin)} ${q(work)} && git -C ${q(other)} push -q origin main:feature`)
        return quiet(run(bash('git rebase origin/main', work))) && remoteBranches().includes('origin/feature')
      }],
      ['skips the fetch when the repository fetched in the last 2 minutes', () => {
        sh(`git -C ${q(other)} push -q origin main:later`)
        return quiet(run(bash('git switch -c topic origin/main', work))) && !remoteBranches().includes('origin/later')
      }],
      ['leaves a command without a remote ref alone', () => quiet(run(bash('git status', work)))],
    ]
  }],

  ['git-prune-gone-branches.sh', run => {
    const origin = path.join(home, 'prune-origin.git'), work = path.join(home, 'prune-work')
    const env = { CLAUDE_PROJECT_DIR: work }
    const notice = r => output(r).systemMessage || ''
    const exists = name => sh(`git -C ${q(work)} branch --list ${name}`) !== ''
    const change = name => `echo ${name} > ${name} && git add ${name} && git commit -q -m ${name}`
    let first = {}
    return [
      ['deletes a gone branch whose commits are on the default branch', () => {
        sh(`git init -q --bare ${q(origin)} && git clone -q ${q(origin)} ${q(work)} 2>/dev/null && cd ${q(work)} && ${change('one')} && git push -q -u origin main && git remote set-head origin main && git switch -q -c merged && ${change('two')} && git push -q -u origin merged && git switch -q main && git merge -q --ff-only merged && git push -q origin main && git switch -q -c unmerged && ${change('three')} && git push -q -u origin unmerged && git switch -q main && git push -q origin --delete merged unmerged`)
        first = run('', { env })
        return first.code === 0 && /^Deleted 1 local branch .*merged \(on origin\/main\)/.test(notice(first)) && !exists('merged')
      }],
      ['keeps a gone branch with commits found nowhere else, and says why', () => /Kept 1 local branch .*unmerged \(not on GitHub\)/.test(notice(first)) && exists('unmerged')],
      ['logs the deleted branch with its hash', () => /\tmerged\t[0-9a-f]{40}\t/.test(fs.readFileSync(path.join(work, '.git/claude-code-deleted-branches.log'), 'utf8'))],
      ['names the kept set only once', () => quiet(run('', { env }))],
      ['reports without deleting under --dry-run', () => { const r = run('', { env, args: ['--dry-run'] }); return r.code === 0 && /^Kept 1 local branch/.test(r.out) && exists('unmerged') }],
    ]
  }],

  ['git-submodule-update-after-switch.sh', run => {
    const sub = path.join(home, 'sm-sub'), top = path.join(home, 'sm-top'), plain = path.join(home, 'sm-plain')
    const post = (command, cwd) => ({ hook_event_name: 'PostToolUse', tool_name: 'Bash', tool_input: { command }, cwd })
    const restored = () => fs.existsSync(path.join(top, 'lib/a'))
    return [
      ['updates the submodules after a switch and hands their status over', () => {
        sh(`git init -q ${q(sub)} && cd ${q(sub)} && echo a > a && git add a && git commit -q -m a && git init -q ${q(top)} && cd ${q(top)} && git submodule add -q ${q(sub)} lib 2>/dev/null && git commit -q -m lib && git submodule deinit -q -f lib`)
        const r = run(post('git switch main', top))
        return r.code === 0 && context(r).startsWith('Ran git submodule update --init') && context(r).includes('git submodule status') && restored()
      }],
      ['finds the repository from git -C', () => {
        sh(`git -C ${q(top)} submodule deinit -q -f lib`)
        return context(run(post(`git -C ${top} switch main`, home))).startsWith('Ran git submodule update') && restored()
      }],
      ['counts gh pr checkout as a switch', () => { sh(`git -C ${q(top)} submodule deinit -q -f lib`); return context(run(post('gh pr checkout 12', top))) !== '' && restored() }],
      ['stays quiet for a command that switches nothing', () => quiet(run(post('git status', top)))],
      ['stays quiet in a repository without submodules', () => { sh(`git init -q ${q(plain)}`); return quiet(run(post('git switch main', plain))) }],
    ]
  }],

  ['memory-plain-characters.sh', run => {
    const memory = path.join(config, 'projects/-plain/memory')
    return [
      ['stays quiet when memory notes use plain characters', () => { write(path.join(memory, 'MEMORY.md'), '- [Note](note.md): a hook\n'); return quiet(run({})) }],
      ['names a note with a long dash and its line', () => {
        write(path.join(memory, 'note.md'), 'line one\nfacts — more\n')
        const r = run({})
        return refused(r) && r.err.includes('note.md:2')
      }],
    ]
  }],

  ['no-meta-prompts.sh', run => {
    const work = path.join(home, 'meta-work'), checkout = path.join(home, 'Projects/dotclaude')
    const message = (dir, name, prompt) => write(path.join(dir, name),
      `Fix the parser\n\nPrompts behind this commit, as given to Claude Code\n(model m, effort e):\n\n1.\n${prompt.split('\n').map(l => `> ${l}`).join('\n')}\n`)
    return [
      ['blocks a commit once when a quoted prompt opens with dotclaude', () => {
        sh(`git init -q ${q(work)} && git init -q ${q(checkout)}`)
        message(work, 'm1.txt', 'dotclaude, add a rule for this')
        return refused(run(bash('git commit -F m1.txt', work)))
      }],
      ['lets the same commit through the second time', () => quiet(run(bash('git commit -F m1.txt', work)))],
      ['finds the words at a sentence start across a wrapped line', () => { message(work, 'm2.txt', 'fix the parser. global\nmemory: keep tabs'); return refused(run(bash('git commit -F m2.txt', work))) }],
      ['lets a prompt through that names dotclaude mid-sentence', () => { message(work, 'm3.txt', 'fix the parser the dotclaude way'); return quiet(run(bash('git commit -F m3.txt', work))) }],
      ['reads a PR body from --body-file', () => { message(work, 'b.md', 'memory: note this'); return refused(run(bash('gh pr create --draft --body-file b.md', work))) }],
      ['lets the configuration checkout through', () => { message(checkout, 'm4.txt', 'dotclaude, add a rule'); return quiet(run(bash('git commit -F m4.txt', checkout))) }],
    ]
  }],

  ['prompt-feedback-box.sh', run => {
    const t = path.join(home, 'feedback.jsonl')
    const box = actions => uses('mcp__ccd_turn__wrap_up', { recap: 'r', ask: 'Commit it?', actions })
    const ask = { hook_event_name: 'PreToolUse', transcript_path: t, tool_use_id: 'toolu_box', tool_input: { recap: 'r', ask: 'Commit it?' } }
    const call = { type: 'assistant', message: { content: [{ type: 'tool_use', id: ask.tool_use_id, name: 'mcp__ccd_turn__wrap_up', input: ask.tool_input }] } }
    const refusal = 'A question in the next-step box ends the turn and takes no text after it. Write the closing reply first.'
    const feedback = says('Fixed it.\n\n**Prompt feedback**\nIt was fine.')
    // Claude Code writes the message holding the reply and the call only after the hook has started.
    const later = records => spawn('bash', ['-c', `sleep 0.3; cat ${q(jsonl(`${t}.later`, records))} >> ${q(t)}`], { stdio: 'ignore' })
    return [
      ['refuses a box with a question while the reply has no Prompt feedback', () => { jsonl(t, [human('fix the bug'), says('Fixed it.'), call]); return decision(run(ask)) === 'deny' }],
      ['lets it through once the reply has the section', () => { jsonl(t, [human('fix the bug'), feedback, call]); return quiet(run(ask)) }],
      ['waits for a reply with the section that reaches the transcript after the hook starts', () => { jsonl(t, [human('fix the bug')]); later([feedback, call]); return quiet(run(ask)) }],
      ['still refuses a late reply without the section', () => { jsonl(t, [human('fix the bug')]); later([says('Fixed it.'), call]); return decision(run(ask)) === 'deny' }],
      ['lets the box through when its own call never reaches the transcript', () => { jsonl(t, [human('fix the bug'), says('Fixed it.')]); return quiet(run(ask)) }],
      ['refuses only once in a turn', () => { jsonl(t, [human('fix the bug'), says('Fixed it.'), toolResult(refusal), call]); return quiet(run(ask)) }],
      ['lets a box without a question through', () => { jsonl(t, [human('fix the bug'), says('Fixed it.')]); return quiet(run({ ...ask, tool_input: { recap: 'r' } })) }],
      ['lets a turn through that a reply button opened', () => {
        jsonl(t, [human('fix the bug'), box([{ label: 'Commit', message: 'commit it' }]), human('commit it'), says('Committed.'), call])
        return quiet(run(ask))
      }],
      ['tells Claude when a prompt repeats a reply button', () => {
        jsonl(t, [human('fix the bug'), says('Fixed it.'), box([{ label: 'Commit', message: 'commit it' }])])
        return /repeats a reply button/.test(context(run({ hook_event_name: 'UserPromptSubmit', transcript_path: t, prompt: 'commit it' })))
      }],
      ['says nothing about a prompt the user typed', () => quiet(run({ hook_event_name: 'UserPromptSubmit', transcript_path: t, prompt: 'now push it' }))],
    ]
  }],

  ['prompt-log.sh', run => {
    const log = prompt => run({ session_id: 'p1', cwd: '/x', prompt })
    const print = (...args) => run('', { args: ['print', ...args], env: { PROMPT_LOG_SESSION: 'p1' } }).out
    return [
      ['logs a prompt and prints nothing', () => quiet(log(`fix the bug in https://example.com/a and tell ${address('bob')}`)) && fs.readFileSync(path.join(config, 'prompt-log/p1.jsonl'), 'utf8').trim().split('\n').length === 1],
      ['prints it for a commit with the addresses replaced', () => print('--commit') === '1.\n> fix the bug in [pasted: an address] and tell [pasted: an address]\n\n'],
      ['leaves out reminders and a prompt sent twice', () => { log('<system-reminder>ignore</system-reminder>'); log('push it'); log('push it'); const out = print(); return out.endsWith('**2.**\n> push it\n\n') && !out.includes('**3.**') }],
      ['replaces a pasted block with its line count', () => { log('look at this <pasted_content id="1">a\nb\nc</pasted_content>'); return print('--from', '3') === '**3.**\n> look at this [pasted: 3 lines]\n\n' }],
      ['wraps long prompts at 72 columns for a commit', () => { log('word '.repeat(40).trim()); const out = print('--commit', '--from', '4'); return out.startsWith('4.\n') && out.split('\n').length > 3 && out.split('\n').every(l => l.length <= 72) }],
      ['redacts a token and writes a home path with ~', () => { log(`use TOKEN=abc123 in ${otherHome}/Projects/x`); return print('--from', '5').includes('TOKEN=[redacted] in ~/Projects/x') }],
      ['fails without a log for the session', () => run('', { args: ['print'], env: { PROMPT_LOG_SESSION: 'none' } }).code === 1],
    ]
  }],

  ['prompts-md.sh', run => {
    const work = path.join(home, 'pm-work'), file = path.join(work, 'PROMPTS.md')
    const body = (subject, prompt, effort = 'high') => `${subject}\n\nIt does it.\n\nPrompts behind this commit, as given to Claude Code\n(model m, effort ${effort}):\n\n1.\n> ${prompt}\n`
    return [
      ['writes PROMPTS.md from the prompts of the commits', () => {
        write(path.join(home, 'pm-1.txt'), body('Add the parser', 'add a parser'))
        sh(`git init -q ${q(work)} && cd ${q(work)} && echo a > a && git add a && git commit -q -F ${q(path.join(home, 'pm-1.txt'))} && echo b > b && git add b && git commit -q -m 'No prompts here'`)
        const r = run('', { cwd: work })
        const text = fs.readFileSync(file, 'utf8')
        return r.code === 0 && /## Add the parser\n\n\d{4}-\d\d-\d\d, commit [0-9a-f]{7}, model m, effort high\.\n\n\*\*1\.\*\*\n> add a parser/.test(text) && !text.includes('No prompts here')
      }],
      ['masks an old prompt and leaves out an effort that is not a level', () => {
        write(path.join(home, 'pm-3.txt'), body('Add the reader', `read ${otherHome}/notes.txt`, 'default'))
        sh(`cd ${q(work)} && echo c > c && git add c && git commit -q -F ${q(path.join(home, 'pm-3.txt'))}`)
        const text = (run('', { cwd: work }), fs.readFileSync(file, 'utf8'))
        return text.includes('> read ~/notes.txt') && !text.includes(otherHome) && !text.includes('effort default') && /commit [0-9a-f]{7}, model m\.\n/.test(text)
      }],
      ['keeps each question and its answer under the prompt', () => {
        write(path.join(home, 'pm-4.txt'), body('Add the asker', 'ask me first') + '\n(p1: keep the old\nparser?)\n> Keep it (Recommended)\n\n(p2: rename it?)\n> no\n')
        sh(`cd ${q(work)} && echo d > d && git add d && git commit -q -F ${q(path.join(home, 'pm-4.txt'))}`)
        const text = (run('', { cwd: work }), fs.readFileSync(file, 'utf8'))
        return text.includes('> ask me first\n\n(p1: keep the old\nparser?)\n> Keep it (Recommended)\n\n(p2: rename it?)\n> no\n')
      }],
      ['lists the commit about to be made first', () => {
        run('', { cwd: work, args: ['--message', write(path.join(home, 'pm-2.txt'), body('Add the printer', 'add a printer'))] })
        const text = fs.readFileSync(file, 'utf8')
        return text.includes('add a printer') && text.indexOf('add a printer') < text.indexOf('add a parser')
      }],
      ['stops on a missing message file', () => run('', { cwd: work, args: ['--message', path.join(home, 'none.txt')] }).code === 2],
    ]
  }],

  ['share-memories.sh', run => {
    const shared = path.join(home, 'shared'), proj = path.join(home, 'Projects/proj')
    const env = { CLAUDE_PROJECT_DIR: proj }
    const memory = path.join(config, 'projects', proj.replace(/[^A-Za-z0-9]/g, '-'), 'memory')
    const dest = path.join(shared, 'proj/me')
    const lock = path.join(config, 'shared-memories-state', `${proj.replace(/[^A-Za-z0-9]/g, '-')}.lock`)
    const note = (name, text) => { const f = write(path.join(memory, name), text); const later = Date.now() / 1000 + 5; fs.utimesSync(f, later, later) }
    const settle = () => { for (let i = 0; i < 50 && fs.existsSync(lock); i++) sleep(100) }
    return [
      ['does nothing without its conf file', () => {
        sh(`git init -q ${q(proj)} && git -C ${q(proj)} remote add origin https://github.com/acme/proj.git && git init -q ${q(shared)}`)
        note('MEMORY.md', '- [Open](open.md): shared\n- [Mine](mine.md): private\n')
        return quiet(run({}, { env })) && !fs.existsSync(dest)
      }],
      ['shares the notes but leaves out one marked share: no', () => {
        write(path.join(config, 'shared-memories.conf'), `dir=${shared}\nowners=acme\nhandle=me\n`)
        note('open.md', '---\nname: open\n---\nThe build runs with make.\n')
        note('mine.md', '---\nname: mine\nmetadata:\n  share: "no"\n---\nMy own habit.\n')
        const r = run({}, { env })
        settle()
        return quiet(r) && fs.existsSync(path.join(dest, 'open.md')) && !fs.existsSync(path.join(dest, 'mine.md')) &&
          fs.readFileSync(path.join(dest, 'MEMORY.md'), 'utf8') === '- [Open](open.md): shared\n'
      }],
      ['holds back a note that looks like it holds a password, and names it', () => {
        note('login.md', 'The test password is "hunter2hunter2".\n')
        const r = run({}, { env })
        settle()
        return r.code === 2 && r.err.includes('login.md') && !fs.existsSync(path.join(dest, 'login.md'))
      }],
      ['leaves repositories of other owners alone', () => {
        sh(`git -C ${q(proj)} remote set-url origin https://github.com/other/proj.git`)
        note('later.md', 'A later note.\n')
        return quiet(run({}, { env })) && !fs.existsSync(path.join(dest, 'later.md'))
      }],
    ]
  }],

  ['stack-held-by-peer.sh', run => {
    const work = path.join(home, 'stack-work'), marker = path.join(work, '.git/claude-stack-holder')
    const holder = path.join(home, 'holder.jsonl'), peer = path.join(home, 'peer.jsonl')
    const env = { CLAUDE_PROJECT_DIR: work }
    const as = (session_id, transcript_path, command) => ({ ...bash(command, work), session_id, transcript_path })
    const active = (file, ago = 0) => jsonl(file, [{ ...says('working'), timestamp: new Date(Date.now() - ago).toISOString() }])
    return [
      ['notes which session started the stack, and the start for the Stop hook', () => {
        sh(`git init -q ${q(work)}`)
        active(holder)
        active(peer)
        return quiet(run(as('s1', holder, 'docker compose up -d'), { env })) && fs.readFileSync(marker, 'utf8') === `s1\t${holder}\n` &&
          fs.existsSync(path.join(work, '.git/claude-stack-started-s1'))
      }],
      ['refuses another session stopping it while the holder is active', () => refused(run(as('s2', peer, 'docker compose down'), { env }))],
      ['refuses another session restarting it', () => refused(run(as('s2', peer, 'npm run start:local'), { env }))],
      ['leaves other docker commands alone', () => quiet(run(as('s2', peer, 'docker ps'), { env }))],
      ['takes the holder as idle when its last reply is old, however fresh the file', () => {
        active(holder, 60 * 60 * 1000)
        fs.appendFileSync(holder, '{"type":"mode","timestamp":null}\n')
        const r = run(as('s2', peer, 'docker compose restart'), { env })
        active(holder)
        sh(`printf 's1\\t%s\\n' ${q(holder)} > ${q(marker)}`)
        return !refused(r)
      }],
      ['lets the holder stop it and clears the note', () => quiet(run(as('s1', holder, 'docker compose down'), { env })) && !fs.existsSync(marker)],
    ]
  }],

  ['stop-running-stack.sh', run => {
    const work = path.join(home, 'stop-work'), t = path.join(home, 'stop.jsonl'), fake = path.join(home, 'fake-docker')
    const env = up => ({ CLAUDE_PROJECT_DIR: work, PATH: `${fake}:${ENV.PATH}`, FAKE_PS: up ? `web\t${work}` : '' })
    const stop = { session_id: 's1', transcript_path: t, stop_hook_active: false }
    const started = () => write(path.join(work, '.git/claude-stack-started-s1'), '')
    return [
      ['sends back a turn that started a stack and left it up', () => {
        sh(`git init -q ${q(work)}`)
        fs.chmodSync(write(path.join(fake, 'docker'), '#!/bin/sh\n[ -n "$FAKE_PS" ] && printf \'%s\\n\' "$FAKE_PS"\nexit 0\n'), 0o755)
        started()
        const r = run(stop, { env: env(true) })
        return refused(r) && r.err.includes('compose project web')
      }],
      ['sends it back only once', () => quiet(run(stop, { env: env(true) }))],
      ['lets it through once the stack is down', () => { started(); return quiet(run(stop, { env: env(false) })) }],
      ['lets the second stop of a turn through', () => { started(); return quiet(run({ ...stop, stop_hook_active: true }, { env: env(true) })) }],
      ['lets a turn through that started nothing', () => quiet(run(stop, { env: env(true) }))],
      ['leaves a stack another session holds to that session', () => {
        started()
        write(path.join(work, '.git/claude-stack-holder'), 's9\t/x\n')
        return quiet(run(stop, { env: env(true) }))
      }],
    ]
  }],

  ['stop-unreachable-claim.sh', run => {
    const t = path.join(home, 'unreachable.jsonl')
    const pane = { type: 'attachment', attachment: { type: 'deferred_tools', names: ['mcp__Claude_Browser__navigate'] } }
    const claim = "I couldn't open the attached PDF. The connector returns file not found."
    const stop = (last, active = false) => ({ session_id: 's1', transcript_path: t, stop_hook_active: active, last_assistant_message: last })
    return [
      ['sends back a claim made without trying the pane', () => {
        jsonl(t, [pane, human('read the pdf'), says(claim)])
        const r = run(stop(claim))
        return refused(r) && r.err.includes('browser pane')
      }],
      ['lets the second stop of a turn through', () => quiet(run(stop(claim, true)))],
      ['reads the reply from the transcript when the input has none', () => refused(run({ session_id: 's1', transcript_path: t, stop_hook_active: false }))],
      ['lets a claim through once the pane ran this turn', () => {
        jsonl(t, [pane, human('read the pdf'), uses('mcp__Claude_Browser__navigate', { url: 'https://example.com' }), says(claim)])
        return quiet(run(stop(claim)))
      }],
      ['does not count a pane call from an earlier turn', () => {
        jsonl(t, [pane, human('open it'), uses('mcp__Claude_Browser__navigate', { url: 'https://example.com' }), says('Done.'), human('read the pdf'), says(claim)])
        return refused(run(stop(claim)))
      }],
      ['lets a reply through that claims nothing', () => {
        jsonl(t, [pane, human('read the pdf'), says('Here is what it says.')])
        return quiet(run(stop('Here is what it says.')))
      }],
      ['lets a reply through about what someone else cannot open', () => {
        const s = "Your colleague probably can't open the links, since the repository is private."
        jsonl(t, [pane, human('draft it'), says(s)])
        return quiet(run(stop(s)))
      }],
      ['lets a session without the pane through', () => {
        jsonl(t, [human('read the pdf'), says(claim)])
        return quiet(run(stop(claim)))
      }],
    ]
  }],

  ['usage-log.sh', run => {
    const t = path.join(config, 'projects/-usage/s.jsonl'), out = path.join(config, 'usage-log/2026-10.jsonl')
    const user = { type: 'user', uuid: 'u1', timestamp: '2026-10-20T10:00:00.000Z', message: { content: 'hi' } }
    const reply = (id, timestamp) => ({ type: 'assistant', uuid: `a-${id}`, parentUuid: 'u1', timestamp, message: { id, model: 'claude-opus-5-5', usage: { input_tokens: 10, output_tokens: 5 } } })
    const logged = () => fs.existsSync(out) ? fs.readFileSync(out, 'utf8').trim().split('\n').map(l => JSON.parse(l).id) : []
    return [
      ['does nothing while the usage mod is missing', () => { jsonl(t, [user, reply('msg_1', '2026-10-20T10:00:05.000Z')]); return quiet(run({ transcript_path: t })) && logged().length === 0 }],
      ['logs each response of the transcript', () => {
        const target = path.join(home, '.claude/mods/session-usage/usage.sh')
        fs.mkdirSync(path.dirname(target), { recursive: true })
        fs.copyFileSync(USAGE_SH, target)
        fs.chmodSync(target, 0o755)
        return quiet(run({ transcript_path: t })) && logged().join() === 'msg_1'
      }],
      ['logs nothing twice', () => quiet(run({ transcript_path: t })) && logged().join() === 'msg_1'],
      ['adds only the responses after the last one logged', () => {
        fs.appendFileSync(t, JSON.stringify(reply('msg_2', '2026-10-20T10:01:00.000Z')) + '\n')
        return quiet(run({ transcript_path: t })) && logged().join() === 'msg_1,msg_2'
      }],
    ]
  }],
]

const hooks = fs.readdirSync(HOOKS).filter(f => f.endsWith('.sh')).sort()
const settings = JSON.parse(fs.readFileSync(path.join(ROOT, 'settings.json'), 'utf8'))
const wired = Object.values(settings.hooks || {}).flat().flatMap(m => m.hooks || []).map(h => (h.command || '').match(/hooks\/([\w.-]+\.sh)/)?.[1]).filter(Boolean)
suites.push(['every hook', () => [
  ['parses with bash -n', () => hooks.every(h => spawnSync('bash', ['-n', path.join(HOOKS, h)]).status === 0)],
  ['has checks in this file', () => hooks.every(h => suites.some(([name]) => name === h))],
  ['settings.json runs only hooks that exist', () => wired.every(h => hooks.includes(h))],
]])

let failed = 0
let total = 0
for (const [hook, make] of suites) {
  console.log(`== ${hook}`)
  for (const [desc, check] of make((input, opts) => run(hook, input, opts))) {
    let pass = false, note = ''
    try { pass = Boolean(check()) } catch (e) { note = `\n    ${String(e.message).split('\n').join('\n    ')}` }
    total++
    if (!pass) failed++
    console.log(`  ${pass ? 'PASS' : 'FAIL'}: ${desc}${note}`)
  }
}
const missing = hooks.filter(h => !suites.some(([name]) => name === h))
if (missing.length) console.log(`no checks for ${missing.join(', ')}`)
fs.rmSync(home, { recursive: true, force: true })
console.log(failed ? `${failed} of ${total} checks failed` : `all ${total} checks passed`)
process.exit(failed ? 1 : 0)
