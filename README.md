# mac-display

`mac-display` is a small native macOS tool for MacBook users who work with an external monitor but still want to keep the lid open and the built-in panel dark.

When at least one external display is connected, the agent:

- saves the current built-in display brightness
- sets the built-in display brightness to `0`
- restores the saved brightness after all external displays are disconnected

## Why this exists

macOS does not provide a built-in way to automatically turn the internal panel dark when an external monitor is attached while keeping the lid open.

A common reason for wanting this setup is convenience: keeping the lid open means `Touch ID`, the built-in keyboard, webcam, speakers, and microphone all remain easy to use, while the internal display stops being visually distracting.

This project implements a lightweight local workaround:

- watch display attach/detach events with `CGDisplayRegisterReconfigurationCallback`
- control the built-in panel brightness through the private `DisplayServices` API
- run as a user `LaunchAgent` at login
- optionally expose a tiny menu bar UI for turning the behavior on or off

## Requirements

- macOS
- a MacBook with a built-in display
- Xcode Command Line Tools with a working `clang`

## Project layout

```text
.
├── build.sh
├── build-ui.sh
├── disable.sh
├── enable.sh
├── install.sh
├── lib
│   └── common.sh
├── status.sh
├── toggle.sh
├── uninstall.sh
├── ui
│   └── main.m
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
build/MacDisplayControl.app
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
- builds a tiny menu bar app
- installs it to `~/Library/Application Support/MacDisplay/MacDisplayAgent`
- installs `~/Applications/MacDisplayControl.app`
- installs a LaunchAgent at `~/Library/LaunchAgents/com.felix021.macdisplay.plist`
- removes the earlier `com.codex.internaldisplayautodim` label if it exists
- opens the menu bar app once in the background

## Lightweight UI

After installation, open `~/Applications/MacDisplayControl.app` to get a small menu bar control.

The menu bar app lets you:

- enable auto dimming
- disable auto dimming
- restore built-in brightness
- open the agent log

The menu bar icon uses MacBook-only transparent PNG assets in `assets/MacDisplayTrayEnabled.png` and `assets/MacDisplayTrayDisabled.png`.

When auto dimming is enabled, the tray icon shows only a MacBook with its screen off. When auto dimming is disabled, it shows only a MacBook with its screen on.

The app icon keeps the external-monitor composition from `assets/MacDisplayEnabled.png` and is generated during `build-ui.sh`.

It does not replace the agent. It is just a friendly controller for the already-installed background behavior.

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
