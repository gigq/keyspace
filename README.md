# Keysmith

`keysmith` is a small native macOS menu bar app for Linux-style hotkey workflows.

It loads global hotkeys from a config file, launches apps, and moves the focused window between desktops.

Current behavior:

- loads bindings from `~/.config/keysmith/keysmith.conf`
- stays in the menu bar
- shows the current desktop number in the menu bar
- registers global hotkeys
- launches apps from config
- moves the focused window to desktop `N`

## How Window Moves Work

macOS does not expose a stable public API for "move the focused window to desktop N".

`keysmith` currently uses a pragmatic workaround:

1. grab the focused window by its title bar
2. trigger the desktop shortcut
3. let macOS carry the window with the desktop switch
4. release the drag

That means this app works best when your setup already supports the manual gesture.

## Prerequisites

Before using `move-window-to-space`, make sure these are true:

1. `keysmith` has Accessibility permission
2. Mission Control desktop shortcuts are set to `cmd+1` through `cmd+0`
3. conflicting screenshot shortcuts are disabled or rebound

The screenshot conflict matters because macOS uses `shift+cmd+3`, `shift+cmd+4`, and `shift+cmd+5` by default.

You can change those in:

`System Settings > Keyboard > Keyboard Shortcuts > Screenshots`

You can change Mission Control desktop shortcuts in:

`System Settings > Keyboard > Keyboard Shortcuts > Mission Control`

## Default Config

The first launch creates this config automatically:

```ini
# Example app launch bindings:
# bind = cmd+enter, launch, Terminal
# bind = cmd+shift+enter, shell, open -na Terminal

bind = shift+cmd+1, move-window-to-space, 1
bind = shift+cmd+2, move-window-to-space, 2
bind = shift+cmd+3, move-window-to-space, 3
bind = shift+cmd+4, move-window-to-space, 4
bind = shift+cmd+5, move-window-to-space, 5
bind = shift+cmd+6, move-window-to-space, 6
bind = shift+cmd+7, move-window-to-space, 7
bind = shift+cmd+8, move-window-to-space, 8
bind = shift+cmd+9, move-window-to-space, 9
bind = shift+cmd+10, move-window-to-space, 10
```

`shift+cmd+10` maps to the physical `0` key.

For these bindings to work, macOS Mission Control desktop shortcuts should be mapped to `cmd+1` through `cmd+0` in `System Settings > Keyboard > Keyboard Shortcuts > Mission Control`.

## Config Format

One binding per line:

```ini
bind = modifiers+key, action, argument
```

Supported actions:

- `launch`
- `shell`
- `move-window-to-space`

Examples:

```ini
bind = cmd+enter, launch, Terminal
bind = cmd+shift+enter, shell, open -na Terminal
bind = cmd+b, launch, Safari
bind = shift+cmd+4, move-window-to-space, 4
```

Supported modifier aliases:

- `cmd`
- `command`
- `super`
- `shift`
- `alt`
- `option`
- `ctrl`
- `control`

The default config path is:

```text
~/.config/keysmith/keysmith.conf
```

The `shell` action runs its argument through `/bin/sh -lc`, which is useful for commands like:

```ini
bind = cmd+shift+enter, shell, open -na Terminal
```

## Running

Build and run from the terminal:

```bash
swift build
swift run
```

You do not need an Xcode project to use or package this app.

## Building A macOS App Bundle

Build a standalone `.app` bundle from the Swift package:

```bash
scripts/build_app.sh
```

That produces:

```text
.build/app/Keysmith.app
```

Install it into `/Applications`:

```bash
scripts/install_app.sh
```

Launch the installed app:

```bash
scripts/open_app.sh
```

The generated app bundle is a menu bar app with `LSUIElement` enabled, so it stays out of the Dock and app switcher.

## Caveats

- `move-window-to-space` requires Accessibility permission because the app needs the focused window ID and posts synthetic input events.
- Desktop tracking still uses private macOS space APIs for the menu bar number.
- Window moves assume a normal draggable title bar.
- Window moves are currently tuned for same-display desktop switching.
- This is a local power-user tool, not an App Store-style distribution target.
