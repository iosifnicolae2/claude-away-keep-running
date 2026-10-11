import type { CommandSpec, EngineInterface, Register, ToolSpec } from 'claude-code'

// Screen off, Mac awake: /away and the screen_off tool turn the physical screens off until the user
// moves the mouse or presses a key; the Mac doesn't sleep or lock, so Claude keeps working.
// Virtual displays (test, recording or streaming displays) stay on.

const BACK_TEXT = 'Screens are off and the Mac stays awake. Move the mouse or press a key to turn them back on.'
const FALLBACK_TEXT = 'Could not turn the screens off, so they went to sleep instead. The Mac may lock.'
const failedText = (error: unknown) => `Could not turn the screens off: ${error instanceof Error ? error.message : String(error)}`
const KEPT_ON_TEXT = 'Could not turn the screens off. They stay on, since display sleep would stop the virtual displays.'

export const AWAY_COMMAND: CommandSpec = {
  name: 'away',
  description: 'Turn the screens off while the Mac stays awake',
}

export const SCREEN_OFF_TOOL: ToolSpec = {
  name: 'screen_off',
  description: 'Turns the physical screens off while the Mac stays awake, until the user moves the mouse or '
    + 'presses a key; virtual displays stay on. Call it when the user says they are leaving and wants the screen off.',
}

/** Starts the blackout detached (a reload can't cut it off) and prints "black" once the screens are dark,
 *  else "failed: why", plus "virtual displays on" when display sleep would stop them. */
export const awayArgv = (root: string) => ['/bin/sh', `${root}/bin/away.sh`]

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register(AWAY_COMMAND)
    await $.tool.register(SCREEN_OFF_TOOL)
    return next(e)
  })
  on('command.run', { command: 'away' }, async $ => ({ text: await screenOff($).catch(failedText) }))
  on('tool.call', { tool: 'mcp__away-keep-running__screen_off' }, async $ => ({ result: await screenOff($).catch(failedText) }))
}

async function screenOff($: EngineInterface): Promise<string> {
  const { stdout } = await $.process.run(awayArgv($.plugin.root))
  if (stdout.startsWith('black')) return BACK_TEXT
  const text = stdout.includes('virtual displays on') ? KEPT_ON_TEXT : FALLBACK_TEXT
  if (text === FALLBACK_TEXT) await $.process.run(['pmset', 'displaysleepnow'])
  $.ui.toast(text)
  return text
}
