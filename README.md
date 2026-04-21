# Keyspace

`keyspace` is a small native macOS menu bar app for people who want a Hyprland-style workspace workflow on macOS.

The goal is not to recreate Hyprland or replace the macOS window manager. The goal is narrower: bring a numbered, keyboard-driven, per-display workspace workflow to Mission Control while keeping the tool lightweight and config-driven.

The reference point for this project is Hyprland's workspace model and the way it lets you describe workspace-specific behavior:

- https://wiki.hypr.land/Configuring/Workspace-Rules/

If you already think in terms of "workspace 1 on this monitor", "move the focused window to workspace 4", and "keep the active workspace state visible", this app is trying to make that feel natural on macOS.

Today, `keyspace` loads global hotkeys from a config file, launches apps, and moves the focused window between numbered desktops.

Current behavior:

- loads bindings from `~/.config/keyspace/keyspace.conf`
- stays in the menu bar
- shows the current desktop number for each display in the menu bar
- registers global hotkeys
- launches apps from config
- moves the focused window to desktop `N`

On multi-display setups, the menu bar label shows one desktop number per display, ordered left to right, for example `2|11`.
Window moves can target either the current display or the secondary display, depending on which action you bind.

## What This Is

`keyspace` is a keyboard-first Mission Control helper. It is designed for people who want:

- numbered desktops that matter
- predictable hotkeys for moving work between desktops
- per-display desktop awareness in the menu bar
- a plain-text config instead of a full desktop environment

## What This Is Not

`keyspace` is not a compositor, tiling window manager, or full Hyprland clone.

It does not replace Finder, Dock, or Mission Control. It layers on top of macOS and tries to make workspace movement feel closer to a Hyprland-style setup using the mechanisms macOS actually gives us.

## How Window Moves Work

macOS does not expose a stable public API for "move the focused window to desktop N".

`keyspace` currently uses a pragmatic workaround:

1. grab the focused window by its title bar
2. trigger the desktop shortcut
3. let macOS carry the window with the desktop switch
4. release the drag

That means this app works best when your setup already supports the manual gesture.

## Prerequisites

The current built-in move workflow assumes these are true:

1. `keyspace` has Accessibility permission
2. Mission Control desktop shortcuts are set to `cmd+1` through `cmd+0`
3. conflicting screenshot shortcuts are disabled or rebound

If you want secondary-display move bindings, also set macOS Mission Control shortcuts for the secondary display to `cmd+option+1` through `cmd+option+0`.

The screenshot conflict matters because macOS uses `shift+cmd+3`, `shift+cmd+4`, and `shift+cmd+5` by default.

You can change those in:

`System Settings > Keyboard > Keyboard Shortcuts > Screenshots`

You can change Mission Control desktop shortcuts in:

`System Settings > Keyboard > Keyboard Shortcuts > Mission Control`

## Default Config

The first launch creates this config automatically. It reflects the current default assumptions about numbered Mission Control desktops on macOS:

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

bind = shift+cmd+option+1, move-window-to-secondary-space, 1
bind = shift+cmd+option+2, move-window-to-secondary-space, 2
bind = shift+cmd+option+3, move-window-to-secondary-space, 3
bind = shift+cmd+option+4, move-window-to-secondary-space, 4
bind = shift+cmd+option+5, move-window-to-secondary-space, 5
bind = shift+cmd+option+6, move-window-to-secondary-space, 6
bind = shift+cmd+option+7, move-window-to-secondary-space, 7
bind = shift+cmd+option+8, move-window-to-secondary-space, 8
bind = shift+cmd+option+9, move-window-to-secondary-space, 9
bind = shift+cmd+option+10, move-window-to-secondary-space, 10
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
- `move-window-to-secondary-space`

Examples:

```ini
bind = cmd+enter, launch, Terminal
bind = cmd+shift+enter, shell, open -na Terminal
bind = cmd+b, launch, Safari
bind = shift+cmd+4, move-window-to-space, 4
bind = shift+cmd+option+4, move-window-to-secondary-space, 4
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
~/.config/keyspace/keyspace.conf
```

Legacy `~/.config/keysmith/keysmith.conf` and `KEYSMITH_CONFIG` overrides are still honored if you already have an older setup.

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

If your shell is pointed at older Apple Command Line Tools but `/Applications/Xcode.app` is installed, the build script automatically prefers Xcode's bundled Swift toolchain.

That produces:

```text
.build/app/Keyspace.app
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
- `move-window-to-secondary-space` uses the same drag-based move flow, but triggers the secondary-display Mission Control shortcut (`cmd+opt+N`) while the window is in transit.
- Desktop tracking still uses private macOS space APIs for the menu bar numbers.
- Window moves assume a normal draggable title bar.
- This is a local power-user tool, not an App Store-style distribution target.
