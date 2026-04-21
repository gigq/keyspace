# Keyspace

`keyspace` is a small native macOS menu bar app for people who want a Hyprland-style workspace workflow on macOS.

The goal is not to recreate Hyprland or replace the macOS window manager. The goal is narrower: bring a numbered, keyboard-driven, per-display workspace workflow to Mission Control while keeping the tool lightweight and config-driven.

The reference point for this project is Hyprland's workspace model and the way it lets you describe workspace-specific behavior:

- https://wiki.hypr.land/Configuring/Workspace-Rules/

If you already think in terms of "workspace 1 on this monitor", "move the focused window to workspace 4", and "keep the active workspace state visible", this app is trying to make that feel natural on macOS.

Today, `keyspace` loads global bindings from a config file, launches apps, moves the focused window between numbered desktops, switches desktops, and can retile the focused display into a master-stack layout on demand.

Current behavior:

- loads bindings from `~/.config/keyspace/keyspace.conf`
- stays in the menu bar
- shows the current desktop number for each display in the menu bar
- registers global keyboard, mouse-button, and scroll bindings
- launches apps from config
- moves the focused window to desktop `N`
- switches desktops with bound keys, mouse buttons, or horizontal scroll input
- tiles the focused display into a manual master layout when requested

On multi-display setups, the menu bar label shows one desktop number per display, ordered left to right, for example `2|11`.
Window moves always target the display the focused window is already on, and `keyspace` resolves the matching Mission Control shortcut from macOS.

## What This Is

`keyspace` is a keyboard-first Mission Control helper. It is designed for people who want:

- numbered desktops that matter
- predictable hotkeys for moving work between desktops
- optional side-wheel or horizontal-scroll bindings for switching desktops
- a manual master-stack tiling action for the current display
- per-display desktop awareness in the menu bar
- a plain-text config instead of a full desktop environment

## What This Is Not

`keyspace` does not replace Finder, Dock, or Mission Control. It layers on top of macOS and tries to make workspace movement and manual retile operations feel closer to a Hyprland-style setup using the mechanisms macOS actually gives us.

It is also not trying to compete directly with tools like:

- [`yabai`](https://github.com/asmvik/yabai), a tiling window manager that controls windows, spaces, and displays much more broadly
- [`AeroSpace`](https://github.com/nikitabobko/AeroSpace), an i3-like tiling window manager that explicitly emulates its own virtual workspaces instead of relying on native macOS Spaces

Those tools are significantly more capable than `keyspace`, but they are solving a larger problem. The goal here is narrower:

- stay close to native Mission Control desktops
- keep the mental model simple and explicit
- avoid replacing the macOS window manager
- provide a minimal, config-driven layer for numbered workspace workflows
- make tiling an explicit action, not an always-on layout daemon

This project exists because I wanted the part of that experience that matters most to me, especially keyboard-driven workspace movement and quick manual retile actions, without adopting a full alternate window management model. In practice, that means deliberately using macOS Spaces instead of inventing a parallel workspace system, and keeping the implementation as small and predictable as possible.

I also wanted something that does not require disabling System Integrity Protection. That tradeoff matters here: `keyspace` is intentionally narrower than `yabai`, but the goal is to stay inside a setup that is easier to install, easier to keep running, and less likely to break across normal macOS updates.

## How Tiling Works

`keyspace` now supports a Hyprland-style master layout for the focused display:

- the focused window becomes the master pane on the left
- other supported windows on that display stack vertically on the right
- running the action again with a different focused window promotes that window to master

This tiling mode is intentionally manual. `keyspace` only retiles when you press a bound key or mouse button. It does not continuously watch every new window and it does not try to enforce a permanent layout in the background.

That is a deliberate design choice. The goal is to keep the behavior flexible and predictable on macOS, avoid the constant resize churn that more aggressive tiling managers can introduce, and let you decide exactly when the current display should be rearranged.

## How Window Moves Work

macOS does not expose a stable public API for "move the focused window to desktop N".

`keyspace` currently uses a pragmatic workaround:

1. grab the focused window by its title bar
2. trigger the desktop shortcut
3. let macOS carry the window with the desktop switch
4. release the drag

That means this app works best when your setup already supports the manual gesture.

## How Space Switching Works

`keyspace` can also switch desktops directly without moving a window.

You can bind that to:

- a keyboard shortcut
- a mouse button
- horizontal scroll input such as the MX Master side wheel

That includes both relative switching (`switch-space-left`, `switch-space-right`) and direct numbered switching (`switch-to-space, N`) for the focused display.

Space switching is still explicit. One trigger produces one desktop change.

- keyboard and mouse-button bindings post the resolved Mission Control shortcut immediately
- scroll-based switching uses a short cooldown so one wheel gesture does not queue several Mission Control transitions at once

The app uses the Mission Control left/right shortcut currently configured in macOS, rather than assuming a fixed hardcoded key combination.

## Prerequisites

The current built-in move workflow assumes these are true:

1. `keyspace` has Accessibility permission
2. Mission Control desktop shortcuts are configured in macOS for the desktops you want to target
3. conflicting screenshot shortcuts are disabled or rebound

The screenshot conflict matters because macOS uses `shift+cmd+3`, `shift+cmd+4`, and `shift+cmd+5` by default.

You can change those in:

`System Settings > Keyboard > Keyboard Shortcuts > Screenshots`

You can change Mission Control desktop shortcuts in:

`System Settings > Keyboard > Keyboard Shortcuts > Mission Control`

## Default Config

The first launch creates this config automatically. It reflects the current default assumption that one set of bindings is enough, because `keyspace` resolves the actual Mission Control desktop shortcut for the focused display:

```ini
# Example app launch bindings:
# bind = cmd+enter, launch, Terminal
# bind = cmd+shift+enter, shell, open -na Terminal
# bind = cmd+1, switch-to-space, 1
# bind = shift+cmd+t, tile-current-display-master
# bind = mouse-4, tile-current-display-master
# bind = scroll-left, switch-space-left
# bind = scroll-right, switch-space-right

bind = cmd+1, switch-to-space, 1
bind = cmd+2, switch-to-space, 2
bind = cmd+3, switch-to-space, 3
bind = cmd+4, switch-to-space, 4
bind = cmd+5, switch-to-space, 5
bind = cmd+6, switch-to-space, 6
bind = cmd+7, switch-to-space, 7
bind = cmd+8, switch-to-space, 8
bind = cmd+9, switch-to-space, 9
bind = cmd+10, switch-to-space, 10

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

For these bindings to work, macOS Mission Control desktop shortcuts should be configured for the desktops you want to target in `System Settings > Keyboard > Keyboard Shortcuts > Mission Control`.

## Config Format

One binding per line:

```ini
bind = modifiers+key, action, argument
bind = modifiers+mouse-N, action, argument
bind = modifiers+scroll-left, action
bind = modifiers+scroll-right, action
```

Supported actions:

- `launch`
- `shell`
- `move-window-to-space`
- `switch-to-space`
- `switch-space-left`
- `switch-space-right`
- `tile-current-display-master`

Examples:

```ini
bind = cmd+enter, launch, Terminal
bind = cmd+shift+enter, shell, open -na Terminal
bind = cmd+b, launch, Safari
bind = cmd+4, switch-to-space, 4
bind = shift+cmd+4, move-window-to-space, 4
bind = scroll-left, switch-space-left
bind = scroll-right, switch-space-right
bind = shift+cmd+t, tile-current-display-master
bind = mouse-4, tile-current-display-master
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

Mouse trigger notes:

- `mouse-1` = left button
- `mouse-2` = right button
- `mouse-3` = middle button
- `mouse-4` and higher = extra mouse buttons
- modifiers work with mouse buttons too, for example `shift+mouse-4`

Scroll trigger notes:

- `scroll-left` and `scroll-right` are for horizontal scroll input
- these are a good fit for devices like the MX Master side wheel
- the top vertical wheel is unaffected unless your mouse software remaps it to horizontal scroll

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
- `move-window-to-space` uses the Mission Control desktop shortcut configured in macOS for the focused display, instead of hardcoding one modifier combination.
- `switch-to-space` uses that same focused-display resolution logic, but switches desktops without dragging a window.
- `switch-space-left` and `switch-space-right` use the Mission Control left/right shortcut configured in macOS.
- scroll-based space switching intentionally uses a cooldown so one wheel gesture does not skip across multiple desktops.
- `tile-current-display-master` is intentionally manual. It does not automatically tile or retile windows when apps open, close, or change focus.
- The tiling action only manages the focused display and skips some window types that are risky to resize continuously.
- Desktop tracking still uses private macOS space APIs for the menu bar numbers.
- Window moves assume a normal draggable title bar.
- This is a local power-user tool, not an App Store-style distribution target.
