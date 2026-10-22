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
ln -sf ~/src/moorings/anchors.lua ~/.hammerspoon/anchors.lua
grep -q 'require("anchors")' ~/.hammerspoon/init.lua 2>/dev/null \
  || cat ~/src/moorings/init.lua >> ~/.hammerspoon/init.lua
```

The symlink means an edit in the repo takes effect on the next Reload. Copy the file instead of
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
- Slack and iTerm are the defaults. See Pins below to name other apps.

### Update and uninstall

Update with `git -C ~/src/moorings pull`, then Reload from the sailboat menu. To remove moorings,
delete `~/.hammerspoon/anchors.lua`, delete the `require("anchors")` line from
`~/.hammerspoon/init.lua`, and choose Reload Config.

## Quickstart

Slack sits at 10% on the left, iTerm at 45% on the right, and everything else stays in the
channel, the open strip in between. Click Slack to expand it to 30%. Click another app to
collapse it. An expanded pin overlaps the channel instead of pushing windows aside, so nothing
in the channel moves when it opens or closes.

To test a change before copying it into `~/.hammerspoon`, run `lua tests/anchors_test.lua` from
the repo root. It drives `anchors.lua` against a fake Hammerspoon and exits non-zero on any
failure.

## Docs

### Menu

The menu bar item holds, top to bottom:

| Item                          | What it does&nbsp;                                               |
|-------------------------------|------------------------------------------------------------------|
| Drop anchor / Weigh anchor    | Freezes and releases the layout. The state survives a reload.    |
| Re-moor now                   | Applies the layout immediately instead of waiting for the poll.  |
| Fill channel                  | Stretches the focused window across the whole channel.           |
| Tidy channel                  | Tiles the 2 or 3 front-most free windows into Halves or Thirds.  |
| Undo tidy                     | Puts every window Fill or Tidy moved back where it started.      |
| Seven width presets           | Sets the left and right edge widths. The choice survives reload. |
| Fullscreen fills the channel  | Turns native fullscreen on the ultrawide into a channel fill.    |
| Edit config                   | Opens `anchors.lua` in the default text editor.                  |
| Console                       | Opens the Hammerspoon Console, where errors are printed.         |
| Reload                        | Reloads the Hammerspoon config.                                  |
| Icon                          | Picks the menu bar glyph. The default is a sailboat.             |

Tidy keeps the windows in their current left-to-right order and then leaves them alone. Undo
restores the position each window had before the first Fill or Tidy since the last undo.

### Pins

Pins, widths and the poll rate live in `M.config` at the top of `anchors.lua`. Each pin names an
app by bundle ID, the side it sits on, an optional `expandPct` it grows to while focused, and an
optional `mainOnly` that moves only the app's main window, so Slack huddles and preference panes
stay put. A side holds up to two pins. One pin fills the strip's full height. Two split it into
top and bottom halves in config order, unless a pin sets `row` to `"top"` or `"bottom"`. A
pinned app that is not running leaves its half empty. Pinned windows on other displays are
pulled onto the ultrawide. Apps listed in `ignoreBundles` are never moved.

```lua
pins = {
  { bundle = "com.tinyspeck.slackmacgap", side = "left", expandPct = 30, mainOnly = true },
  { bundle = "com.googlecode.iterm2", side = "right" },
},
ignoreBundles = { "us.zoom.xos" },
```

Find an app's bundle ID with `osascript -e 'id of app "Spotify"'`.

Once a preset has been chosen, its widths win over `leftPct` and `rightPct` in the file.

### Channel rules

A free window that strays into an edge is pushed back into the channel. One wider than the
channel is narrowed to fit, and it grows back toward its old width when a wider preset opens the
channel up again, unless it was resized by hand in between. Windows already inside the channel
are never touched, and windows on other displays are left alone.

A free window that goes native fullscreen on the ultrawide, which the green button does, leaves
fullscreen and fills the channel instead. Untick Fullscreen fills the channel to get true
fullscreen back, or use Drop anchor for a while.

### Guards

Nothing moves while the mouse button is down, so dragging a window is never fought mid-drag. A
window that keeps moving away from where moorings puts it, four times inside ten seconds, is left
alone for a minute and the Console says so. Re-moor now clears those holds. Without
Accessibility permission nothing moves and the Console says that once. Widths that leave less
than a 10% channel fall back to 10 and 45. While the layout is frozen, Fill, Tidy and Undo are
grayed out.

### Screens

Moorings acts on the widest display whose aspect ratio is at least `minAspect`. With no such
display attached it does nothing, so a laptop screen or a 16:9 monitor is safe.

## License

Apache-2.0. See `LICENSE`.
