# away-keep-running

A Claude Code plugin for macOS: `/away` turns your screens off while the Mac stays awake, so Claude keeps working while you're gone. Open this file to install it, or to see how it works.

- 🌙 **`/away`**: the screens go dark at once. The Mac doesn't sleep or lock, so running sessions, builds and agents carry on.
- 🔇 **The Mac goes silent**: the sound is muted while you're away and comes back as it was, even after a crash or reboot ([bin/sound.sh](bin/sound.sh)).
- 🖱️ **Move the mouse or press a key** and every screen comes back, with its brightness as it was.
- 🧪 **Virtual displays stay on**: test, recording or streaming displays other apps made keep running.
- 🤖 **The model can do it too**: say "I'm heading out, turn the screen off" and Claude calls the `screen_off` tool.

## Install

Type this at the prompt of a Claude Code terminal session:

```
/plugin install away-keep-running --marketplace iosifnicolae2/claude-away-keep-running
```

Answer `y` to add the marketplace, then pick the user scope. Or from a shell:

```sh
claude plugin marketplace add iosifnicolae2/claude-away-keep-running
claude plugin install away-keep-running@claude-away-keep-running --scope user
```

## How it works

- **External screens** are turned off as if unplugged, so each monitor gets no signal and goes to its own standby.
- **One screen stays on** to hold your windows and the Dock: the built-in, else the main one. It gets a black window and brightness 0, through Apple's DisplayServices or, for external screens, over DDC/CI.
- **`caffeinate -d -i -s`** keeps the Mac and its displays awake underneath, so the Mac never locks.
- **The first real mouse move or key press** brings everything back. Whatever ended the blackout, a restore step undoes each change it noted.
- **If the blackout fails**, the displays sleep instead (`pmset displaysleepnow`), unless virtual displays are on, since display sleep would stop them.
- **It never sends DDC standby or power off**: some monitors (an LG and a Philips here) stayed dark after that, their buttons dead.

The pieces:

| File | What it does |
| --- | --- |
| [hooks/register.ts](hooks/register.ts) | Registers `/away` and the `screen_off` tool. |
| [bin/away.sh](bin/away.sh) | Starts the blackout detached, so a plugin reload can't cut it off. |
| [bin/blackout.js](bin/blackout.js) | The blackout itself (JavaScript for Automation). |
| [bin/display.sh](bin/display.sh), [bin/display_helper.swift](bin/display_helper.swift) | Lists screens, turns them off and on, sets DDC brightness. A universal binary ships prebuilt; with `swiftc` installed, a changed source is compiled once into `~/.cache/away-keep-running`. |

Needs macOS 12 or newer. No Accessibility permission: it reads how long since the last input instead of watching events.

## Develop

```sh
claude plugin validate .
claude plugin test .
sh tests/sound.test.sh
sh scripts/build-display-helper.sh   # after changing bin/display_helper.swift or .h; commit the binary and .sha256
claude --plugin-dir .                # a session with your local copy loaded
```

Try the blackout without Claude Code: `sh bin/away.sh`. See which screens it would cover: `osascript -l JavaScript bin/blackout.js --plan "$(sh bin/display.sh screens | cut -f1 | paste -sd, -)"`.

Extracted from [better-tasks](https://github.com/iosifnicolae2/better-tasks), where `/away` started.

## License

MIT
