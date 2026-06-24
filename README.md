# mac-display

`mac-display` is a small native macOS agent for MacBook users who work with an external monitor and want the built-in panel to go black automatically.

When at least one external display is connected, the agent:

- saves the current built-in display brightness
- sets the built-in display brightness to `0`
- restores the saved brightness after all external displays are disconnected

## Why this exists

macOS does not provide a built-in way to automatically turn the internal panel dark when an external monitor is attached while keeping the lid open.

This project implements a lightweight local workaround:

- watch display attach/detach events with `CGDisplayRegisterReconfigurationCallback`
- control the built-in panel brightness through the private `DisplayServices` API
- run as a user `LaunchAgent` at login

## Requirements

- macOS
- a MacBook with a built-in display
- Xcode Command Line Tools with a working `clang`

## Project layout

```text
.
├── build.sh
├── disable.sh
├── enable.sh
├── install.sh
├── lib
│   └── common.sh
├── status.sh
├── toggle.sh
├── uninstall.sh
└── src
    └── main.m
```

## Build

```bash
bash build.sh
```

This produces:

```text
build/MacDisplayAgent
```

## Run manually

Run one evaluation:

```bash
./build/MacDisplayAgent --once --verbose
```

Run a dry run without changing brightness:

```bash
./build/MacDisplayAgent --dry-run --once --verbose
```

Force a one-time restore:

```bash
./build/MacDisplayAgent --restore --once --verbose
```

## Install at login

```bash
bash install.sh
```

The installer:

- builds the binary
- installs it to `~/Library/Application Support/MacDisplay/MacDisplayAgent`
- installs a LaunchAgent at `~/Library/LaunchAgents/com.felix021.macdisplay.plist`
- removes the earlier `com.codex.internaldisplayautodim` label if it exists

## Lightweight on/off controls

After installation, you do not need to uninstall the project to temporarily stop it.

Enable the agent:

```bash
bash enable.sh
```

Disable the agent:

```bash
bash disable.sh
```

Toggle it:

```bash
bash toggle.sh
```

Check current status:

```bash
bash status.sh
```

Notes:

- `disable.sh` restores the built-in display brightness once, then unloads the `LaunchAgent`
- `enable.sh` loads the existing `LaunchAgent` again without reinstalling files

## Uninstall

```bash
bash uninstall.sh
```

## How it works

The implementation is in [src/main.m](src/main.m).

Key behaviors:

- detect the built-in display with `CGDisplayIsBuiltin`
- count connected external displays with `CGGetOnlineDisplayList`
- debounce rapid display reconfiguration events
- save the previous brightness only when it is meaningfully above zero
- restore the saved brightness when no external display remains

## Limitations

- This sets the built-in display brightness to `0`; it does not truly disconnect the internal display.
- It uses private macOS APIs, so future macOS releases may require updates.
- It is intended for local use and is not App Store compatible.
