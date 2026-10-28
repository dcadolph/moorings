<p align="center">
  <img src="moorings.jpg" alt="Three boats on moorings in a calm cove" width="100%">
</p>

<h1 align="center">moorings</h1>

<p align="center">
  <a href="https://macmoorings.com"><img src="https://img.shields.io/badge/macmoorings.com-Download_for_Mac-0a6c74?style=for-the-badge&logo=apple&logoColor=white" alt="macmoorings.com: Download for Mac"></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-0a6c74" alt="License: Apache-2.0"></a>
  <img src="https://img.shields.io/badge/swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/platform-macOS_14+-lightgrey?logo=apple&logoColor=white" alt="Platform: macOS 14 or later">
</p>

A free window manager for every Mac. Snap windows with a key or a drag, and on an ultrawide, pin
your always-on apps to the edges.

A native menu bar app, signed and notarized, with a full set of window shortcuts, drag snapping,
tiling, saved layouts and profiles on every display, and up to four apps parked on the edges of an
ultrawide.
[FEATURES.md](FEATURES.md) lists everything you get.

## How moorings started

There are some windows I don't want to have to find. I just want them to be right there on the
screen, ready to go, no matter how much jumping around I'm doing in other apps or windows.

With a standard sized monitor, apps like Rectangle deliver everything you could reasonably want.
You only have enough space to anchor or park a persistent window, so the fact that Rectangle's
Todo mode only locks down one specified app or window is logical.

For an ultrawide user, the goal posts shift a bit. You still want Rectangle features like
setting your window widths, organizing your windows, snap shortcuts, and more. However, a single
Todo zone just doesn't cut it. For many people optimizing what they have on screen, both sides
of the ultrawide typically need to be parked apps or they go to waste.

Long story short, I created moorings because I wanted for free what Rectangle wanted to charge
me, I wanted more flexibility, and I wanted the customization and the ability to tailor things
to my ultrawide way of working.

## Contents

- [How moorings started](#how-moorings-started)
- [Requirements](#requirements)
- [Install](#install)
- [Windows](#windows)
- [Quickstart](#quickstart)
- [Docs](#docs)
- [Moving from the Hammerspoon version](#moving-from-the-hammerspoon-version)
- [Coming from Rectangle](#coming-from-rectangle)
- [Support](#support)
- [License](#license)

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel
- Accessibility permission for Moorings
- Any other window manager quit, since both would move windows

## Install

With Homebrew:

```sh
brew install --cask dcadolph/tap/moorings
```

Or download `moorings_vX.Y.Z_macos_universal.dmg` from the
[latest release](https://github.com/dcadolph/moorings/releases/latest), open it, and
double-click Moorings. After one okay it copies itself into Applications, starts from there,
ejects the disk image, and moves it to the Trash. Dragging Moorings onto Applications works too,
and then it asks once before trashing the disk image. The zip is still attached for scripts and
Homebrew. Both are signed with a Developer ID
and notarized by Apple, and `SHA256SUMS` on the release lists their checksums.

Open Moorings. A small sailboat appears in the menu bar. The first time, a banner asks for
Accessibility access: click it, turn on Moorings in Privacy & Security, and the sailboat is
ready. Until then the sailboat shows a warning sign and the menu's first entry opens the same
settings page. Nothing needs a restart after the grant.

To update, take the offer at the top of the menu, or run `brew upgrade --cask moorings`. To
uninstall, quit Moorings and run `brew uninstall --cask moorings`, or drag it to the Trash.

## Windows

An early Windows build holds apps in the side strips of an ultrawide the same way. It runs on
Windows 11 with a monitor 21:9 or wider and lives in the notification area.

- Anchor an app from the tray menu to Left top, Left bottom, Right top or Right bottom, and its
  window stays in that strip.
- Any other window that lands on a strip goes back into the channel. A held window moved by hand
  is released, and Ctrl+Alt+Backspace puts it back.
- The Rectangle shortcuts on Ctrl+Alt: Ctrl+Alt+Left gives a window the channel's left half, and
  Ctrl+Alt+Enter lifts a held window over the channel.
- Strip widths, Pause and Launch at login are in the tray menu.

Each green run of the
[windows workflow](https://github.com/dcadolph/moorings/actions/workflows/windows.yml) attaches
a `moorings-windows-<commit>` zip, which needs a GitHub sign-in to download. Unzip it, keep the
files together, and run `MooringsWin.exe`. The `README-windows.txt` inside walks through the
first run.

## Quickstart

1. Click the app you want on an edge, open the Moorings menu, choose **Anchor** *app*, and pick a
   slot. Its window moves to that edge and stays there.
2. Press Control-Option-Left in any other window. It takes the left half of the channel, the
   open middle of the ultrawide, or of the whole screen on any other display. Press again for two
   thirds and one third.
3. Drag a window to a screen edge. A footprint shows where it lands. Let go to snap it.
4. Click an anchored window's green button to lift it over the channel. Click again to lower it.

## Docs

How Moorings compares with every other Mac window manager, row by row with a check for each: [COMPARISON.md](COMPARISON.md).

### Menu

The menu rebuilds each time it opens. From the top: an update offer when one is waiting, the
anchor toggle (Weigh anchor lets windows drift, Drop anchor holds them again), Re-moor now,
Anchor or Unanchor the front app, Cast off this window, a Re-moor entry for each released app,
then the Anchored apps, Window, Lift, Workspaces, Profiles, Widths and Heights folders, Settings,
Launch at login, Check for updates now, Check for updates automatically, Tip the harbormaster, and
Quit. Quit pulls the sailboat under the water before Moorings exits, unless Reduce Motion is on.

### Window actions

Every action works on the front window. On the ultrawide it works inside the channel, and on any
other display inside the usable screen. Left and right halves cycle through 1/2, 2/3 and 1/3 on
repeat presses, and the first and last thirds step across the three thirds. The Window folder
lists every action with its shortcut, so it doubles as a cheat sheet. The default keymap:

| Action&nbsp;              | Shortcut&nbsp;  | In plain English&nbsp;                           |
|---------------------------|-----------------|--------------------------------------------------|
| Left, right half          | ⌃⌥← ⌃⌥→         | Control + Option + Left Arrow or Right Arrow     |
| Top, bottom half          | ⌃⌥↑ ⌃⌥↓         | Control + Option + Up Arrow or Down Arrow        |
| Quarters                  | ⌃⌥U ⌃⌥I ⌃⌥J ⌃⌥K | Control + Option + U, I, J or K                  |
| First, center, last third | ⌃⌥D ⌃⌥F ⌃⌥G     | Control + Option + D, F or G                     |
| Two thirds                | ⌃⌥E ⌃⌥R ⌃⌥T     | Control + Option + E, R or T                     |
| Maximize                  | ⌃⌥↩             | Control + Option + Return                        |
| Maximize height           | ⌃⌥⇧↑            | Control + Option + Shift + Up Arrow              |
| Center                    | ⌃⌥C             | Control + Option + C                             |
| Larger, smaller           | ⌃⌥= ⌃⌥-         | Control + Option + Equals or Minus               |
| Restore                   | ⌃⌥⌫             | Control + Option + Delete                        |
| Previous, next display    | ⌃⌥⌘← ⌃⌥⌘→       | Control + Option + Command + Left or Right Arrow |
| Cycle slot windows        | ⌃⌥⌘↓ ⌃⌥⌘↑       | Control + Option + Command + Down or Up Arrow    |

Window > Keymap switches to another preset, or to None to start from a blank slate. Fourths, sixths, eighths, ninths, twelfths,
sixteenths, vertical thirds, sixths and eighths, corner thirds, almost maximize, center
prominently and the move actions have no key until you record one in Settings.

Window > Displays sends the front window to display one through nine, counted left to
right with a row of displays above another counted first. Specified sizes it to 1680 by 1050
points unless you change it, centered and shrunk to fit. Window > One axis
makes it wider, narrower, taller or shorter in 30 point steps, or doubles or halves one side
toward the edge you pick. The side names such as `left-side` and `center-section` are aliases of
the halves. On an anchored window, Maximize lifts it and Restore puts it back in its slot. Window >
Ignore shortcuts in *app* turns the shortcuts off while that app is in front, so its own keys
work.

Window > Size and move also moves the window to an edge, a corner or the center without resizing
it. Undo move and Redo move step a window back through its last ten moves by Moorings and forward
again, and each window keeps its own history.

Window > Arrow mode has four actions that read where the window is. Left and right take a half,
then step across quarters and on to the next display. Up maximizes a free window or moves a half
or quarter up a step. Down restores a maximized window, steps a half or quarter down, or
minimizes a free one. Window > Keymap > Windows puts them on Control-Option arrows. Fill left and
Fill right grow the window sideways to the next window or the edge of the area and keep its far
edge.

Window > Front app brings the app's next or previous window forward, minimizes or closes the
front window, or minimizes or closes every other window of the app. Anchored windows stay put.

### Links

Scripts, launchers and Stream Decks can drive Moorings with links:

```sh
open "moorings://action?name=left-half"
open "moorings://workspace?name=Desk"
open "moorings://settings"
open "moorings://banner?text=hello"
open "moorings://status"
open "moorings://selftest"
```

Shortcuts can run any action too. Run Moorings Action takes an action name and offers the list,
chains, workspaces and profiles included, so a shortcut, Spotlight or Siri can move a window.

`status` writes the screens, slots and every window Moorings sees to the unified log under the
`com.dcadolph.moorings` subsystem.

### Custom sizes, gap, buttons and chains

Settings > Sizes adds sizes as shares of the area: x and y place the top left corner, w and h set
the size, from 0 to 1. Each size can take a shortcut and shows in Window > Custom sizes. Window >
Gap leaves 4 to 16 points around each window an action places, and Settings > Layout sets any gap
up to 100. Settings > Layout > Mouse buttons binds the middle, back, forward and sixth buttons to
any action. Settings > Layout > Title bar buttons binds a click on the red, yellow or green button,
plain or with Shift, Option or Command, to any action. A click you leave unbound keeps the
button's own behavior.

Settings > Menu builds chains: a named list of actions that runs one step per press on the same
window, and stops on the last step or loops back to the first. A chain takes its own shortcut,
mouse button and menu entry. The same tab pins actions to the top of the Window folder and hides
the ones you never use. The `show-menu` action opens the Moorings menu under the pointer, from a
shortcut or a mouse button, without bringing Moorings to the front.

### Behavior choices

Settings > Behavior sets each of these, and the JSON file Settings exports keeps them under
`settings.behavior`.

- `subsequentExecution`: what pressing the same shortcut again does. `cycle-sizes` (the default)
  steps a half through 1/2, 2/3 and 1/3. `traverse-displays` sends a right half on to the next
  display as its left half, and a left half to the previous display as its right half.
  `traverse-and-cycle` does that until it would wrap, then cycles sizes.
  `cycle-displays` places the same action on the next display, `cycle-quadrants` steps a corner
  across the four quarters, `switch-sides` flips a half to the other side, and `none` stays put.
- `screenEdgeGapTop`, `screenEdgeGapBottom`, `screenEdgeGapLeft`, `screenEdgeGapRight` and
  `screenEdgeGapTopNotch` keep points free at the screen edges. `gapsOnMainOnly` limits them to the
  main display and `applyGapsToMaximize` set to false lets maximize ignore them.
- `stageSize` is the width the Stage Manager strip takes when it shows, and
  `alwaysAccountForStage` keeps it free even when it does not. On the ultrawide the strip only
  comes off a channel that reaches the screen edge.
- `enhancedUI` turns an app's Enhanced UI off while an action or a drag snap moves its window, so
  apps such as Slack land on the exact frame. `automatic` (the default) turns it back on afterward except in Chromium
  browsers.
- `moveCursor` moves the pointer to the middle of a window that a shortcut, the menu or a link
  moved.
- `unsnapRestore` (on by default) gives a window that a shortcut, the menu or a drag snap placed
  its earlier size back as soon as you drag it away, with the window kept under the pointer.
- `doubleClickTitleBar` (off by default) maximizes a window when you double-click its title bar,
  and restores it when the window still sits where that maximize put it. It works only when System
  Settings > Desktop & Dock > Double-click a window's title bar is set to Do Nothing, so macOS and
  Moorings never both act. `doubleClickIgnoredApps` lists bundle ids it leaves alone.
- `hideMenuBarIcon` hides the icon. Open Moorings again to reach Settings.
- `screensOrderedByX` orders displays for the display actions: `y-then-min-x` (the default),
  `min-x` or `mid-x`.
- `specifiedWidth` and `specifiedHeight` set the Specified size in points.
- `repeatedMaximizeRestores` makes Maximize pressed again restore the window, while it still sits
  where that maximize put it.
- `centerHalfCycles` steps Center half through 1/2, 2/3 and 1/3 on repeat presses, as the sides do.
- `halvesPreserveOtherAxis` keeps the window's height and top on a left or right half, and its width
  and left edge on a top or bottom half.
- `minimumWindowWidth` and `minimumWindowHeight` (25% by default) are the smallest share of the area
  Smaller, the one-axis Smaller and the Halve actions shrink a window to.
- `animate` (off by default, experimental) slides a window a shortcut, the menu or a link moves
  over 150 ms instead of jumping. Drag snap, anchors, push back and lift never animate, and the
  last write always lands on the exact frame.

### Throw, grid and hover

Settings > Behavior > Throw with a held key picks Right Option, Right Command, Right Control or
Fn. Hold it and move the pointer. A short move toward a side or corner picks a half or a quarter,
a longer one picks thirds, sixths, maximize or center, and a footprint shows where the window
will land. Let go and the window that was under the pointer goes there, focused or not. Arrow
keys switch to a grid of cells instead, Shift-arrows grow the pick, Return applies it and Escape
cancels. It is off until you pick a key.

Window > Size and move > Grid lays a grid of cells over the front window's area. Drag across the
cells you want, or click one, and the window fills them. Arrow keys and Return work too, and
Escape or a click off the grid puts it away. Grid uses the size set in Settings > Behavior, and an
action named like `grid:8x6` has its own.

Settings > Behavior > Move and resize by hovering takes two sets of keys. Hold the move keys and
the window under the pointer follows it, no click needed. Hold the resize keys and it grows and
shrinks from its nearest corner. The same section takes keys for shared edge resize: hold them and
drag the edge two side by side windows share, and both resize as one divider. All three are off
until you pick keys, and anchored windows stay put.

### Stash

Window > Stash parks the front window at the left, right or bottom edge with a sliver showing.
Dragging a window to one of those edges with Command held does the same. Rest the pointer on the
sliver and the window slides out, move away and it slides back. Click in it, or choose Stash
again, to end the stash, and Unstash all brings every parked window back. An edge another display
touches is skipped, and on the ultrawide so is a side with anchored apps. Parked windows go back
when Moorings quits.

### Organize

Window > Organize tiles the free windows on the front window's display in columns, rows or a
grid, tiles one app's windows in a grid, cascades them all or one app's, cycles the windows
stacked at the front window's corner, and mirrors them left to right. Tidy channel lines up the
two or three front windows side by side. Undo tidy puts back every window a fill, tidy or action
moved. Windows are stacked when their top-left corners sit together, within one overlap offset
step of each other, whatever their size. With Settings > Behavior > Show how many windows are
stacked on, resting the pointer at a window's top-left corner shows the count at its top-right
corner, and moving the pointer hides it.

Window > Tiling keeps the free windows of each display in a tall, wide, columns, rows or BSP
layout as windows open and close, inside the channel on the ultrawide. A window you drag floats
until you choose a layout again. Grow main and Shrink main change the main window's share, and
the focus and swap actions reach the window to the left, right, above or below, with tiling on or
off. Tiling actions have no keys until you record them.

### Workspaces

Workspaces > Save workspace stores the slots, widths, heights and the frame of every free window
under a name. Recall puts it back, matching windows by app and title. Recall with these displays
ties a workspace to the displays attached now, and plugging into that set recalls it.

Settings > Workspaces has two switches per workspace. Open missing apps makes a recall open the
apps it names that are not running and place their windows once they show. Recall on any display
change brings it back whenever a display comes or goes. App rules, on the same tab, name an app
and an action, and the app's first window goes there when it appears.

### Profiles

Profiles > Save current as profile stores the shortcuts, keymap, custom sizes, gap, snapping,
behavior, stacking, chains, menu, app rules, mouse buttons and title bar clicks under a
name. Switching to it, from the menu, a shortcut or `moorings://action?name=profile:<name>`, puts
them back and recalls the workspaces it groups, in order. Settings > Workspaces renames a profile,
picks its workspaces, records its shortcut, and saves the current settings into it. Anchored apps
and strip sizes belong to the desk, so a profile never moves them.

### Settings window

Open it from the menu, or open Moorings again while it runs. It records shortcuts, edits custom
sizes, renames and ties workspaces, picks the keymap, snap areas, gap, mouse buttons and fullscreen
handling, and exports or imports every choice as one JSON file. Imported workspaces
come back untied, since the file may come from another desk. Restore defaults, under the tabs,
asks once and then puts shortcuts, snapping and behavior back to their defaults.
Anchored apps, strip sizes, ignored apps, custom sizes and workspaces stay.

### Snap by dragging

Drag a window to an edge or corner of any display and a footprint shows where it lands. Edges
give halves, corners quarters, the top edge maximizes, and the bottom edge gives thirds. On the
ultrawide the strips stand in for the screen edges. Hold Option while dropping a window on a
strip to anchor its app in that slot. Window > Snap windows by dragging turns it off.

Settings > Snapping changes the map on every display but the ultrawide: the action for each edge
and corner on landscape and portrait displays, areas that never snap, keys that must be held to
snap, edge margins and corner sizes. The keys to hold apply on the ultrawide too. It also styles
the footprint (fill opacity, border, color, fade) and can add a haptic tap on a Force Touch
trackpad as the footprint moves to a new zone.

Custom areas map any part of a display, as shares from 0 to 1, to an action or a size of your
own, and they come before the edges. The snap panel, once turned on, appears when you pause for a
moment while dragging: a row of targets above the pointer, each drawn as the part of the screen
it fills. Drop the window on one to apply it. Settings > Snapping picks and orders the targets.
Custom areas work on every display but the ultrawide, where the strips keep their zones. The
panel works everywhere.

### Anchored apps

An ultrawide has four slots, a top and bottom on each side. An app alone on its side takes the
full height. A side with nothing anchored gives its width to the channel. Widths and Heights set
the strip widths and the split between rows, with presets. Anchored apps that are not running
open in the background at launch.

Adjust strips, in either menu, a bindable shortcut action named adjust-strips, opens an editor
over the ultrawide. Each inner strip edge has a drag bar, arrows and a typed percent field, and
each strip's row line has up and down arrows and a field. Arrow keys step 1 percent and Shift
steps 5. Tab moves between fields, Return keeps the changes and Escape puts back the widths and
heights from when it opened. The arrows, Return and Escape reach the editor whichever app is in
front, and go back to your apps when it closes. Windows move live. Typed values clamp so a strip
never goes narrower than its app's minimum and the channel keeps its minimum share. Settings,
Layout, has a Strips section with number fields for left width, right width and each side's top
row.

An app that will not shrink to its strip keeps its own width, and its strip grows to fit. Widths
names the app and disables the presets that would squeeze it.

### Lift and release

Click an anchored window's green button, or use the Lift folder, to lift it over its strip and
the channel at full height. Click again to lower it. Drag an anchored window away and Moorings
lets it go, with a banner that says to click its green button or press Restore. The Re-moor entry
and Re-moor now also bring it back.

### The channel

A free window that strays into a strip is pushed back, and one too wide is narrowed and grows
back when the channel widens. Cast off this window lets one window cover the strips until it
closes or you click again. A free window's green button fills the channel, and a second click
puts it back. Native fullscreen on the ultrawide fills the channel instead, and on an anchored
app puts it back in its slot. The Lift folder has a switch for each.

### Guards

Nothing moves while the mouse button is down. A window that keeps fighting its place is left
alone for a minute. Weigh anchor freezes everything, including the shortcuts and the green
button. Moorings checks the layout when a window opens, closes or moves, when an app launches or hides,
and when displays change. No layout timer runs while nothing moves.

### Selftest

Quit TextEdit, leave a slot empty, keep your hands off the mouse, and open
`moorings://selftest`. Moorings anchors TextEdit in the empty slot, opens throwaway documents,
checks each layout rule against them, then puts your slots back and quits TextEdit. Each check
logs PASS or FAIL, and a banner gives the total.

`moorings://selftest?apps=com.tinyspeck.slackmacgap,org.videolan.vlc` checks other apps instead:
it moves, resizes, snaps and restores the front window of each, logs PASS or FAIL per case with
the app's version, and puts the window back. A resize the app holds at its own minimum size logs
MIN instead of FAIL.

## Moving from the Hammerspoon version

Versions before 1.5.0 ran inside Hammerspoon. To move over, run `moorings uninstall` and
`brew uninstall moorings`, then install the cask. Slots, widths and choices start fresh. Choose
your anchored apps once from the menu.

## Coming from Rectangle

Quit the old app first so the two do not fight over the same keys. Settings > General > Import
from Rectangle brings over your shortcuts, gaps, snapping and behavior choices, and asks before
it applies them. The default keymap matches the old one. Links and scripts keep the same action
names and need the `moorings://action?name=<action>` URL. [COMPARISON.md](COMPARISON.md) lists
every feature with the check behind it.

## Support

moorings is free and will stay free. If I ever stop maintaining it, I'll archive it, and the code
stays open.

## License

Apache-2.0. See `LICENSE`.
