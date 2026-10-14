import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const AWAY = {
  command: 'away',
  args: '',
  origin: { kind: 'composer' },
  presentation: { isFullscreen: true, columns: 80 },
} as const

/** Answers the engine's side; records every command the plugin runs. */
function fakeHost(on: On, awaySays = 'black') {
  const ran: string[][] = []
  on('process.run', ($, e) => {
    ran.push([...e.argv])
    const stdout = e.argv[1]?.endsWith('/bin/away.sh') ? awaySays : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.toast', () => ({ value: undefined }))
  return ran
}

const isAway = (argv: string[]) => argv[0] === '/bin/sh' && /\/bin\/away\.sh$/.test(argv[1] ?? '')

test('/away starts the detached blackout', async ($, on) => {
  const ran = fakeHost(on)
  const { text } = await $.command.run(AWAY)
  expect(text).toContain('Screens are off')
  expect(ran.filter(isAway)).toHaveLength(1)
})

test('the screen_off tool does what /away does', async ($, on) => {
  const ran = fakeHost(on)
  await $.tool.call({ tool: 'mcp__away-keep-running__screen_off', tool_use_id: 't1' })
  expect(ran.filter(isAway)).toHaveLength(1)
})

test('when the blackout fails, the displays sleep instead', async ($, on) => {
  const ran = fakeHost(on, 'failed: no answer in 5 s')
  const { text } = await $.command.run(AWAY)
  expect(text).toContain('may lock')
  expect(ran).toContainEqual(['pmset', 'displaysleepnow'])
})

test('when the blackout fails while virtual displays run, nothing sleeps', async ($, on) => {
  const ran = fakeHost(on, 'failed: no answer in 5 s\nvirtual displays on')
  const { text } = await $.command.run(AWAY)
  expect(text).toContain('virtual displays')
  expect(ran).not.toContainEqual(['pmset', 'displaysleepnow'])
})

test('session start registers /away and the screen_off tool, and puts back sound a crashed away left muted', async ($, on) => {
  const commands: string[] = [], tools: string[] = []
  const ran = fakeHost(on)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => { commands.push(e.name); return { value: { command: e.name } } })
  on('tool.register', ($, e) => { tools.push(e.name); return { value: { tool: `mcp__away-keep-running__${e.name}` } } })
  await $.session.start({ cwd: '/project', surface: 'terminal', isInteractive: true })
  expect(commands).toEqual(['away'])
  expect(tools).toEqual(['screen_off'])
  expect(ran.some(argv => /\/bin\/sound\.sh$/.test(argv[1] ?? '') && argv[2] === 'recover')).toBe(true)
})
