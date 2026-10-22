<p align="center">
  <img src="moorings.jpg" alt="Three boats on moorings in a calm cove" width="640">
</p>

<h1 align="center">moorings</h1>

<p align="center"><em>Ultrawide aficionados: anchor your screens in style.</em></p>

[Hammerspoon](https://www.hammerspoon.org) config that pins chosen apps to the left or right edge
of an ultrawide screen and keeps every other window in the channel between them. Slack on the
left and iTerm on the right are the defaults. It replaces Rectangle for one person's desk.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Quickstart](#quickstart)
- [Docs](#docs)
- [License](#license)

## Requirements

- macOS with an ultrawide display (aspect ratio of 2.2 or wider)
- Hammerspoon with Accessibility permission
- Rectangle quit, since both apps move windows

## Install

Four steps. When they are done a sailboat sits in the menu bar at the top right of the screen.

**1. Get the files and Hammerspoon.** Skip the `brew` line if Hammerspoon is already installed.

```sh
git clone https://github.com/dcadolph/moorings.git ~/src/moorings
brew install --cask hammerspoon
```

**2. Wire moorings into Hammerspoon.** Paste this whole block. It is safe to run twice.

```sh
mkdir -p ~/.hammerspoon
ln -sfn ~/src/moorings ~/.hammerspoon/moorings
grep -q 'require("anchors")' ~/.hammerspoon/init.lua 2>/dev/null \
  || cat ~/src/moorings/init.lua >> ~/.hammerspoon/init.lua
```

The link means an edit in the repo takes effect on the next Reload. Copy the folder instead of
linking it to pin a version.

**3. Start Hammerspoon and allow it.** Open Hammerspoon from Applications. macOS asks for
Accessibility access. Click Open System Settings, switch Hammerspoon on under Privacy &
Security, then Accessibility. Quit Rectangle first if you use it, since both apps move windows.

**4. Reload once.** Click the Hammerspoon hammer in the menu bar and choose Reload Config. The
sailboat appears next to it. Moorings registers Hammerspoon as a login item itself, so it comes
back after every restart and there is nothing to turn on in Preferences.

### If the sailboat is missing

- Open the hammer menu and choose Console. A line starting with `moorings:` says what is wrong.
- Hammerspoon is not running. Open it from Applications.
- The menu bar is full. macOS hides the overflow behind the notch. Quit a menu bar app or
  Command-drag icons closer together, and look under System Settings, Menu Bar for items that
  are switched off.
- The sailboat shows but nothing moves. That is expected on a display that is not ultrawide.
  Moorings only acts on a screen at least 2.2 times wider than it is tall, and it needs the
  Accessibility permission from step 3.
- Slack and iTerm are the defaults. See Locked apps below to choose other apps.

### Update and uninstall

Update with `git -C ~/src/moorings pull`, then Reload from the sailboat menu. To remove moorings,
delete the `~/.hammerspoon/moorings` link, delete the moorings lines from
`~/.hammerspoon/init.lua`, and choose Reload Config.

## Quickstart

Slack sits at 10% on the left, iTerm at 45% on the right, and everything else stays in the
channel, the open strip in between. Click Slack to expand it to 30%. Click another app to
collapse it. An expanded pin overlaps the channel instead of pushing windows aside, so nothing
in the channel moves when it opens or closes.

To lock another app, click it, open the sailboat menu, choose Locked apps, Pin frontmost app,
then pick a slot. The wider and narrower items under Widths move each strip by 1%, and the
Channel label shows what is left in the middle.

Press Control-Option-Left to put the focused window in the left half of the channel. Press it
again for two thirds, then one third. The Window folder in the menu lists every action with its
shortcut.

To test a change, run `lua tests/anchors_test.lua`, `lua tests/geometry_test.lua` and
`lua tests/actions_test.lua` from the repo root. The first drives `anchors.lua` against a fake
Hammerspoon, the second checks the frame math in `geometry.lua`, the third checks the keymap and
menu families in `actions.lua`, and each exits non-zero on any failure.

## Docs

### Menu

The top of the menu holds Drop anchor and Re-moor now, then four folders, then Reload.

| Item                       | What it holds&nbsp;                                                             |
|----------------------------|---------------------------------------------------------------------------------|
| Drop anchor / Weigh anchor | Freezes and releases the layout and the shortcuts. Survives a reload.           |
| Re-moor now                | Applies the layout immediately instead of waiting for the poll.                 |
| Window                     | Every window action by family, each showing its shortcut.                       |
| Window, Organize           | Fill channel, Tidy channel into Halves or Thirds, and Undo tidy.                |
| Locked apps                | Four slot rows, Pin frontmost app, and Reset to defaults.                       |
| Widths                     | The Channel label, the wider and narrower steppers, seven presets.              |
| Settings                   | Fullscreen fills the channel, Ignore frontmost app, Icon, Edit config, Console. |
| Reload                     | Reloads the Hammerspoon config once every moorings file compiles.               |

Tidy keeps the windows in their current left-to-right order and then leaves them alone. Undo
tidy restores the position each window had before the first Fill, Tidy or window action since
the last undo.

### Window actions

Window actions work on the focused window, on every display. On the ultrawide the channel is the
screen, so a left half is the left half of the channel and the pins never move. On any other
display the screen is the whole area below the menu bar. A pinned window ignores actions.

| Shortcut        | Action&nbsp;                                                          |
|-----------------|-----------------------------------------------------------------------|
| ⌃⌥ arrows       | Left, right, top and bottom half. Left and right cycle 1/2, 2/3, 1/3. |
| ⌃⌥ U I J K      | Top left, top right, bottom left and bottom right quarter.            |
| ⌃⌥ D F G        | First, center and last third. First and last walk the thirds.         |
| ⌃⌥ E R T        | First, center and last two thirds.                                    |
| ⌃⌥ Return       | Maximize.                                                             |
| ⌃⌥⇧ Up          | Maximize height.                                                      |
| ⌃⌥ C            | Center.                                                               |
| ⌃⌥ = and -      | Larger and smaller by 30 points on every edge not at the screen edge. |
| ⌃⌥ Delete       | Restore the frame the window had before its first action.             |
| ⌃⌥⌘ Left, Right | Previous and next display, keeping the window's relative place.       |

This is Rectangle's recommended keymap. Fourths, sixths, eighths, ninths, corner thirds, almost
maximize, center prominently and the four moves have no default key and run from the Window
folder. Rebind or unbind any action in `shortcuts` in the config:

```lua
shortcuts = {
  ["left-half"] = { mods = { "ctrl", "alt" }, key = "h" },
  maximize = false,
},
```

An unknown action, a bad key, or two actions on one key are reported in the Console at load. A
key set in the config beats a default on the same key. Shortcuts turn off while an app in
`ignoreBundles` is frontmost, and Settings, Ignore frontmost app does the same for the app you
were just using. That choice survives a reload.

### Custom sizes and gaps

`sizes` in the config adds your own positions to the Window, Custom sizes folder. `x`, `y`, `w`
and `h` are shares of the area from 0 to 1 and default to the whole area. `width` and `height`
in points size the window and center it in that share. `shortcut` binds a key.

```lua
sizes = {
  { title = "Reading", x = 0.25, w = 0.5, shortcut = { mods = { "ctrl", "alt" }, key = "y" } },
  { title = "Video", width = 1280, height = 720 },
},
gapPx = 10,
```

`gapPx` leaves that many points between the area's edges and the window, and between two
windows side by side, for every action except almost maximize and the display moves. An entry
without a title, with shares outside 0 to 1 or past the area's edge, or a gap outside 0 to 100
is reported in the Console and skipped.

### Locked apps

Each strip holds up to two locked apps, so there are four slots: Left top, Left bottom, Right
top and Right bottom. One app on a side fills the strip's full height. Two split it 50/50. Each
slot row in the menu shows its app and opens a list of running apps plus Empty. Picking an app
that already sits in another slot moves it, so an app is never in two slots. An app that is
locked but not running leaves its half empty, and the other app keeps its half.

Pin frontmost app is the fast path. The menu bar does not take focus, so the frontmost app is
the one you were just using. Choices are saved in Hammerspoon settings and win over the pins in
the config file. Reset to defaults clears them.

A locked app keeps the `expandPct` and `mainOnly` the config gives it. Apps the config does not
name get no expand, and all of their windows move into the slot. Expand on focus widens an app
only within its own half of the strip.

### Pins

Pins, widths and the poll rate live in `M.config` at the top of `anchors.lua`. Each pin names an
app by bundle ID, the side it sits on, an optional `expandPct` it grows to while focused, and an
optional `mainOnly` that moves only the app's main window, so Slack huddles and preference panes
stay put. A side holds up to two pins. One pin fills the strip's full height. Two split it into
top and bottom halves in config order, unless a pin sets `row` to `"top"` or `"bottom"`. A
third pin on a side, a row other than top or bottom, and two pins asking for the same row are
each reported in the Console once at load. Pinned windows on other displays are pulled onto the
ultrawide. Apps listed in `ignoreBundles` are never moved or offered in the menu. This example
stacks Slack over Notes on the left:

```lua
pins = {
  { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top", expandPct = 30,
    mainOnly = true },
  { bundle = "com.apple.Notes", side = "left", row = "bottom" },
  { bundle = "com.googlecode.iterm2", side = "right" },
},
ignoreBundles = { "us.zoom.xos" },
```

Find an app's bundle ID with `osascript -e 'id of app "Spotify"'`.

The config pins apply until Locked apps choices are saved. A width chosen from the menu, by a
preset or a step, wins over `leftPct` and `rightPct` in the file.

### Channel rules

A free window that strays into an edge is pushed back into the channel. One wider than the
channel is narrowed to fit, and it grows back toward its old width when a preset or step opens
the channel up again, unless it was resized by hand in between. Windows already inside the channel
are never touched, and windows on other displays are left alone.

A free window that goes native fullscreen on the ultrawide, which the green button does, leaves
fullscreen and fills the channel instead. Untick Fullscreen fills the channel to get true
fullscreen back, or use Drop anchor for a while.

### Guards

Nothing moves while the mouse button is down, so dragging a window is never fought mid-drag. A
window that keeps moving away from where moorings puts it, four times inside ten seconds, is left
alone for a minute and the Console says so. Re-moor now clears those holds. Without
Accessibility permission nothing moves and the Console says that once. Widths that leave less
than a 10% channel fall back to 10 and 45, and a step that would do so is grayed out. While the
layout is frozen, Fill, Tidy, Undo and every window action are grayed out, and the shortcuts do
nothing.

### Screens

Moorings acts on the widest display whose aspect ratio is at least `minAspect`. With no such
display attached the layout does nothing, so a laptop screen or a 16:9 monitor is safe. Window
actions still work there, and nothing moves until one is pressed.

## License

Apache-2.0. See `LICENSE`.
