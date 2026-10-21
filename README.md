# moorings

![Three boats on moorings in a calm cove](moorings.jpg)

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

```sh
brew install --cask hammerspoon
mkdir -p ~/.hammerspoon
ln -s "$PWD/anchors.lua" ~/.hammerspoon/anchors.lua
cat init.lua >> ~/.hammerspoon/init.lua
```

The symlink means an edit in the repo takes effect on the next Reload. Copy the file instead to
pin a version.

Open Hammerspoon, grant Accessibility in System Settings under Privacy & Security, then choose
Reload Config from its menu bar icon. Moorings registers Hammerspoon as a login item itself, so
there is nothing to turn on in Preferences.

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
stay put. Several pins can share a side, and they stack in the same strip. Pinned windows on
other displays are pulled onto the ultrawide. Apps listed in `ignoreBundles` are never moved.

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

None. Personal use.
