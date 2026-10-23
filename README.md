<p align="center">
  <img src="moorings.jpg" alt="Three boats on moorings in a calm cove" width="640">
</p>

<h1 align="center">moorings</h1>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-0a6c74" alt="License: Apache-2.0"></a>
  <a href="https://www.hammerspoon.org"><img src="https://img.shields.io/badge/built_on-Hammerspoon-0a6c74" alt="Built on Hammerspoon"></a>
  <a href="https://www.lua.org"><img src="https://img.shields.io/badge/lua-5.4-2C2D72?logo=lua&logoColor=white" alt="Lua 5.4"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple&logoColor=white" alt="Platform: macOS">
</p>

A free window manager for any Mac, keyboard or mouse. The permanent home for your always-on apps
on an ultrawide.

Built on [Hammerspoon](https://www.hammerspoon.org), with Rectangle's keymap, drag snapping,
tiling and saved layouts on every display, and up to four apps parked on the edges of an
ultrawide. [FEATURES.md](FEATURES.md) lists everything you get.

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
- [Quickstart](#quickstart)
- [Docs](#docs)
- [Support](#support)
- [License](#license)

## Requirements

- macOS
- Hammerspoon with Accessibility permission
- Rectangle quit, since both apps move windows

## Install

Four steps. When they are done the moorings mark, a small sailboat, sits in
the menu bar at the top right of the screen.

**1. Get the files and Hammerspoon.** Skip the cask line if Hammerspoon is already installed.
With Homebrew:

```sh
brew install --cask hammerspoon
brew install dcadolph/tap/moorings
```

Or from a clone, to edit moorings yourself:

```sh
brew install --cask hammerspoon
git clone https://github.com/dcadolph/moorings.git ~/src/moorings
```

**2. Wire moorings into Hammerspoon.** It is safe to run twice. With Homebrew run
`moorings setup`, from a clone run `~/src/moorings/moorings setup`. Setup links
`~/.hammerspoon/moorings` to the files and adds three marked lines to
`~/.hammerspoon/init.lua`, backing it up first. `moorings doctor` checks the result. With a clone
the link means an edit in the repo takes effect on the next Reload.

**3. Start Hammerspoon and allow it.** Open Hammerspoon from Applications. macOS asks for
Accessibility access. Click Open System Settings, switch Hammerspoon on under Privacy &
Security, then Accessibility. Quit Rectangle first if you use it, since both apps move windows.
If the macOS prompt was closed, moorings shows a warning sign in the menu bar and a banner.
Click either one, or choose Grant Accessibility access at the top of the menu, to open the same
settings page.

**4. Check for the mark.** Once the switch is on, the warning sign turns into the moorings mark
on its own and a short message says Accessibility is granted. If the warning stays, click it
and choose Reload. Moorings registers Hammerspoon as a login item itself, so it comes back after
every restart and there is nothing to turn on in Preferences.

### If the mark is missing

- Open the hammer menu and choose Console. A line starting with `moorings:` says what is wrong.
- Hammerspoon is not running. Moorings starts it again within 30 seconds unless you chose Quit
  moorings. To start it sooner, open it from Applications.
- The menu bar is full. macOS hides the overflow behind the notch. Quit a menu bar app or
  Command-drag icons closer together, and look under System Settings, Menu Bar for items that
  are switched off.
- The mark shows but no apps park at the edges. That is expected on a display that is not
  ultrawide. Parked apps only act on a screen at least 2.2 times wider than it is tall.
- A warning sign shows in place of the mark. Accessibility is missing. See step 3.
- Nothing is anchored until you choose an app. See Quickstart below.

### Update and uninstall

Moorings checks GitHub once a day for a new release. When one is out, Update moorings and its
version show at the top of the menu. Choosing it runs `brew upgrade moorings` for a Homebrew
install or `git pull --ff-only` for a clone, then reloads, and a message says which version is
now running. When no newer version arrived, the message says so and moorings checks GitHub again
at once. Nothing installs until you choose it.
Settings, Check for updates now asks at once. To stop the daily check, untick Settings, Check for
moorings updates. To update by hand, run `brew upgrade moorings` or
`git -C ~/src/moorings pull`, then Reload. When Hammerspoon is older than the version moorings
was checked on, the top of the menu says so and offers Hammerspoon's own update check.

To remove moorings, choose Quit moorings, then run `moorings uninstall`. It removes the link, the
lines setup added to `init.lua` and the restart helper, and leaves anything else alone. With
Homebrew, `brew uninstall moorings` afterward removes the files.

Moorings keeps Hammerspoon running. A small helper checks every 30 seconds and starts Hammerspoon
again if it quit or crashed, without reopening apps you closed. It is a shell command, not an app,
so System Settings lists it under Login Items as sh. Quit moorings removes the helper and quits
Hammerspoon until your next login. To stop the restarts and keep Hammerspoon running, untick
Settings, Restart if it stops. If moorings was deleted without Quit moorings, the helper stops
restarting Hammerspoon on its own. Remove its file with:

```sh
launchctl bootout gui/$(id -u)/moorings.keepalive
rm ~/Library/LaunchAgents/moorings.keepalive.plist
```

Hammerspoon keeps itself current. Moorings turns on its built-in updater, which checks a few
times a day, downloads new versions quietly and installs them the next time Hammerspoon quits,
such as at a restart. Your Accessibility permission carries over. To be asked first instead,
untick Settings, Keep Hammerspoon up to date.

## Quickstart

Moorings starts with nothing anchored, so no window moves until you choose an app. On an
ultrawide, a message the first time says how. To anchor an app, click it, open the moorings menu,
choose Anchor *app* near the top, then pick a slot. Picking an app from a slot's list opens it the
way a Dock click does, and the list ends with Choose app…, which browses for any app.

With Slack in Left top and iTerm in Right top, Slack sits at 10% on the left, iTerm at 45% on the
right, and everything else stays in the channel, the open strip in between. Click Slack's green
button to lift it over the channel at full height, and click it again to lower it. Drag an
anchored window somewhere else and moorings lets it go with a short message. Its green button or
Control-Option-Delete brings it home. The wider and narrower items under Widths move
each strip by 1%, and the Channel label shows what is left in the middle. When two apps share a
side, Heights sets how tall the top one is, from 10% to 90%, and the bottom one takes the rest. A
calendar at 10% over Slack at 90% is Heights, Left side, Top 10%.

Press Control-Option-Left to put the focused window in the left half of the channel. Press it
again for two thirds, then one third. The Window folder in the menu lists every action with its
shortcut.

To test a change, run `for t in tests/*_test.lua; do lua $t; done`
from the repo root. The anchors test drives the whole tool against a fake Hammerspoon, and the
others check the frame math, the keymap and menu families, the drag zones, the organize
layouts, workspace matching, key recording, the banner and the restart helper. Each exits
non-zero on any failure.

## Docs

### Menu

The top of the menu holds Weigh anchor, Re-moor now and Anchor *app*, then seven folders, then
Reload and Quit moorings. Update moorings shows above them all while a new release is out.

| Item                          | What it holds&nbsp;                                                                                                                                                                      |
|-------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Update moorings (*version*)   | Shown while a newer release is out. Installs it the way moorings was installed, then reloads.                                                                                            |
| Weigh anchor / Drop anchor    | Weigh lets every window drift and rests the shortcuts. Drop holds the layout again. Survives a reload.                                                                                   |
| Re-moor now                   | Applies the layout immediately instead of waiting for the poll.                                                                                                                          |
| Re-moor *app*                 | Shown for each anchored window released after you moved it. Puts it back.                                                                                                                |
| Anchor *app* / Unanchor *app* | The app you were just using. Anchor picks one of the four slots. Unanchor frees its slot and leaves the window.                                                                          |
| Anchored apps                 | Four slot rows, each with running apps and Choose app…, then Unanchor all apps and Reset to defaults.                                                                                    |
| Window                        | Every window action by family, each showing its shortcut.                                                                                                                                |
| Window, Organize              | Tile, cascade, cycle and reverse, then Fill channel, Tidy channel and Undo tidy.                                                                                                         |
| Lift                          | One entry per anchored window. Lifts it over its strip and the channel, or lowers it back.                                                                                               |
| Widths                        | The Channel label, a note for an empty side, the wider and narrower steppers, seven presets.                                                                                             |
| Heights                       | A label per side, the taller and shorter steppers, and seven top row presets for each side.                                                                                              |
| Workspaces                    | Saved layouts, each with Recall, a display tie, Replace and Delete, then Save current layout.                                                                                            |
| Settings                      | Settings window, the fullscreen and snapping toggles, Keep Hammerspoon up to date, Restart if it stops, the two update checks, Keymap, Ignore frontmost app, Icon, Edit config, Console. |
| Reload                        | Reloads the Hammerspoon config once every moorings file compiles.                                                                                                                        |
| Quit moorings                 | Stops moorings and Hammerspoon, and the restart helper with them, until the next login.                                                                                                  |

Tidy keeps the windows in their current left-to-right order and then leaves them alone. Undo
tidy restores the position each window had before the first Fill, Tidy or window action since
the last undo.

### Window actions

Window actions work on the focused window, on every display. On the ultrawide the channel is the
screen, so a left half is the left half of the channel and anchored windows never move. On any other
display the screen is the whole area below the menu bar. An anchored window ignores actions.

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
folder. Settings, Keymap switches to Spectacle's set instead: ⌥⌘ arrows for halves, ⌃⌘ and ⌃⇧⌘
Left and Right for corners, ⌃⌥ Right and Left to walk the thirds, ⌥⌘ F to maximize, ⌥⌘ C to
center, ⌃⌥⇧ Right and Left for larger and smaller, and ⌥⌘ Z to restore. `keymap` in the config
sets the starting choice. Rebind or unbind any action in `shortcuts` in the config:

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

### Links and mouse buttons

Any action runs from a link, so a script, a launcher or a Stream Deck can call it:

```sh
open -g "hammerspoon://moorings?action=left-half"
open -g "hammerspoon://moorings?action=size:Reading"
```

The action names are the ones Rectangle uses, such as `next-display` and `tile-all`. A custom
size is `size:` followed by its title. An unknown name is reported in the Console.

`mouseButtons` in the config binds extra mouse buttons, 2 for the middle button and 3 and up for
side buttons. A bound button's clicks run the action and go no further, so a browser does not
also go back. Unbound buttons pass through, and every button passes through while the layout is
frozen or an ignored app is frontmost.

```lua
mouseButtons = { [3] = "previous-display", [4] = "next-display" },
```

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

### Organize

The Window, Organize folder moves every free window on the focused window's screen at once. On
the ultrawide that means the windows in the channel, and anchored windows never move.

| Action&nbsp;                   | What it does&nbsp;                                                 |
|--------------------------------|--------------------------------------------------------------------|
| Tile columns                   | Side by side columns, in left to right order.                      |
| Tile rows                      | Stacked rows, in top to bottom order.                              |
| Tile all                       | A near square grid read left to right, top to bottom.              |
| Cascade all                    | Steps every window down and right, front-most on top.              |
| Cascade active app             | The same for the focused app's windows only.                       |
| Cycle stacked windows          | Brings forward the next window sharing the focused window's frame. |
| Cycle stacked windows backward | The same, the other way.                                           |
| Reverse all                    | Mirrors every window left to right.                                |
| Tidy channel                   | Tile columns for the 2 or 3 front-most windows.                    |

None has a default shortcut. Bind one in `shortcuts`, such as `["tile-all"] = { mods = { "ctrl",
"alt" }, key = "a" }`. Undo tidy and Restore put tiled and cascaded windows back.

### Workspaces

Workspaces, Save current layout asks for a name and saves the four slots, the strip widths and
heights, and the frame of every free window on every display. Recall puts them all back. Windows are
matched by app and then by title, so two Safari windows each go back to their own place. A window
whose app is not running, or whose display is not attached, stays where it is and the Console says
how many.

Recall when these displays connect ties a workspace to the displays attached now. Plugging the
laptop into that setup again recalls it. Each setup holds one workspace, and starting or
reloading moorings never recalls anything. A workspace also runs from a shortcut or a link as
`workspace:` followed by its name:

```lua
shortcuts = { ["workspace:Desk"] = { mods = { "ctrl", "alt" }, key = "1" } },
```

### Settings window

Settings, Settings window opens a window for everything above without editing the Lua file.
Shortcuts lists every action by family. Click Record and press the keys to rebind one, Clear to
leave it unbound, or Reset to go back to the config or the keymap. Shortcuts are paused while a
key is being recorded so the press reaches the window, and a key without Control, Option or
Command is refused unless it is a function key. Custom sizes adds, edits, renames and deletes
sizes, and a size's key follows a rename. Workspaces saves, recalls, ties and deletes them.
Icon offers every menu bar icon choice described below. General sets the keymap, snapping and
the gap.

Choices made in the window are saved in Hammerspoon settings and win over the config file, the
same way a width picked from the menu does. A size saved with the title of a config size takes
its place.

### Menu bar icon

Settings, Icon picks what sits in the menu bar. The built-in emoji are grouped into Boats, Sea
life, Tools, and Hearts and shapes. Custom… takes 1 to 5 characters, such as initials or an
emoji, counted as Unicode code points, so an emoji built from several joined parts may not fit.
The moorings mark at the top of the list is the default: a template image of the logo, drawn in
the menu bar's own color. If it cannot load, the Sailboat emoji stands in and the Console says
why. Surprise me picks a different built-in emoji at random, Default icon goes back to the
mark, and Undo icon change swaps back to the choice before the last one.

Your own icons appear in a Yours folder. List them in the config under `icons`, each with a
`name` and either a `glyph` or an `image` path:

```lua
icons = {
  { name = "Initials", glyph = "DA" },
  { name = "Logo", image = "/Users/you/Pictures/logo.svg" },
},
```

PNG, SVG, PDF and JPEG files in `~/.hammerspoon/moorings/icons/` are listed there too, by file
name. Images are drawn as template images, so a black shape on a clear background follows the
light or dark menu bar. Moorings never creates that folder. Open icons folder reveals it, or says
how to create it when it is missing. The settings window has the same choices.

### Snap by dragging

Drag a window by its title bar to a screen edge and a footprint shows where it will land. Let go
to snap it there. On a normal display this is Rectangle's map: the left and right edges give
halves, the top edge maximizes, the corners give quarters, the stretch of an edge next to a
corner gives the top or bottom half, and the bottom edge gives thirds. Sliding along the bottom
from a side third into the middle gives two thirds.

On the ultrawide the screen edges belong to the anchored apps, so the strips stand in for them.
Dragging over the left strip snaps to the channel's left half and over the right strip to its right
half. The top or bottom of a strip gives that corner's quarter of the channel. The top edge above
the channel maximizes into the channel, and its bottom edge gives the channel's thirds.

Hold Option while dropping a window on a strip to park its app there instead. The top half of a
strip is that side's top slot and the bottom half its bottom slot, and the footprint shows the
slot. This is the same as picking the app in Anchored apps, so an app already in another slot
moves. An anchored window can be parked in another slot this way.

A drag that resizes a window and a drag inside a window never snap, and an anchored window only
parks. Untick Settings, Snap by dragging to turn snapping and parking off.

iTerm resizes in whole character cells, so its windows land a few points short of a snap target.
Run `defaults write com.googlecode.iterm2 DisableWindowSizeSnap -integer 1` to turn that off.

### Anchored apps

Anchored apps need an ultrawide display, one at least 2.2 times wider than it is tall. Each strip
holds up to two anchored apps, so there are four slots: Left top, Left bottom, Right top and Right
bottom. One app on a side fills the strip's full height. Two split it 50/50. Each slot row in the
menu shows its app and opens a list of running apps plus Empty. Picking an app that already sits
in another slot moves it, so an app is never in two slots. An app that is anchored but not running
leaves its half empty, and the other app keeps its half.

A side with no anchored app belongs to the channel. Free windows can use the whole width up to
that edge, Lift on the other side reaches it, and Widths says "Right side empty: part of the
channel". The last few points of that edge still snap a window and, with Option held, park an
app there. Anchoring an app on the side gives the strip back at its chosen width.

Anchor *app* near the top of the menu is the fast path. The menu bar does not take focus, so it
names the app you were just using, and turns into Unanchor *app* once that app holds a slot. Choices are saved in Hammerspoon settings and win over the anchors
in the config file. Unanchor all apps empties every slot, so every window is free until you pick
an app again. Weigh anchor is the pause: it keeps your choices and only stops holding windows.
Reset to defaults goes back to the anchors in the config file, which anchors nothing unless you
add apps there.

An anchored app keeps the `expandPct` the config gives it. Apps the config does not name get no
expand. Expand on focus widens an app only within its own row of the strip.

### Anchors in the config

Anchored apps, widths and the poll rate live in `M.config` at the top of `anchors.lua`. Each entry
in `anchored` names an app by bundle ID, the side it sits on, and an optional `expandPct` it grows to
while focused. An anchored app holds one window, the main window when moorings first sees the app,
and keeps holding it until it closes. The app's other windows are free, so Slack huddles, preference
panes and a tab torn out of iTerm stay out of the slot. An Open or Save picker is never held, so an
app that starts on its file picker, such as TextEdit, leaves its slot empty until a document opens. A side holds up to two anchored apps. One
fills the strip's full height. Two split it into top and bottom rows in config order, unless an
entry sets `row` to `"top"` or `"bottom"`. A third entry on a side, a row other than top or bottom,
and two entries asking for the same row are each reported in the Console once at load. Anchored
windows on other displays are pulled onto the ultrawide. Apps listed in `ignoreBundles` are never
moved or offered in the menu. This example stacks Slack over Notes on the left:

```lua
anchored = {
  { bundle = "com.tinyspeck.slackmacgap", side = "left", row = "top", expandPct = 30 },
  { bundle = "com.apple.Notes", side = "left", row = "bottom" },
  { bundle = "com.googlecode.iterm2", side = "right" },
},
ignoreBundles = { "us.zoom.xos" },
```

Find an app's bundle ID with `osascript -e 'id of app "Spotify"'`.

The config anchors apply until Anchored apps choices are saved. A width chosen from the menu, by a
preset or a step, wins over `leftPct` and `rightPct` in the file. The top row of each side is
`leftTopPct` and `rightTopPct` percent of the strip's height, 50 by default and 10 to 90, and a
height chosen from Heights wins over them the same way.

### Lift and release

An anchored window can rise over its strip and the channel at full height, stopping at the other
strip. Click its green button, press Maximize (Control-Option-Return) while it is in front, or pick
it in the Lift folder. The same again lowers it. Moorings keeps the click away from macOS, so the
green button on an anchored window never starts native fullscreen.

An anchored window you drag or resize yourself is released. Moorings leaves it where you put it and
shows a short message saying how to bring it back: its green button, Restore
(Control-Option-Delete), or Re-moor *app* at the top of the menu. Re-moor now brings every released
window home at once. The macOS window menu on the green button counts as your hand too, since
moorings cannot tell which entry ran. Anchored windows moved after Weigh anchor, or by a
display change, are put back instead of released.

Some apps refuse to get narrower than a set width. A window like that keeps its own width against
the outer edge, and its strip grows to fit it, so free windows never slide under it. Widths then
says which app holds the side, such as "Left 13% in use: Slack needs 668 pt", and disables the
narrower step and the presets below it. The channel always keeps at least 10% of the display.
Moorings remembers the width until the window closes or you choose Re-moor now.

### Channel rules

A free window that strays into an edge is pushed back into the channel. One wider than the
channel is narrowed to fit, and it grows back toward its old width when a preset or step opens
the channel up again, unless it was resized by hand in between. Windows already inside the channel
are never touched, and windows on other displays are left alone.

Clicking the green button of a free window on the ultrawide fills the channel instead of starting
native fullscreen, and a second click puts the window back where it was. Option-click it for the
macOS zoom. A free window that goes native fullscreen another way, such as Control-Command-F, leaves
fullscreen and fills the channel. An anchored window that ends up in fullscreen goes back to its
slot. Untick Fullscreen fills the channel or Fullscreen keeps anchored apps in their slots to get
true fullscreen back for that kind of window, or use Weigh anchor for a while.

Hovering over the green button shows a menu that belongs to macOS, not to moorings. Its Move &
Resize, Fill & Arrange, Full Screen and Move to display entries are macOS window tiling. Moorings
cannot add to that menu. It only reacts after macOS moves the window: Full Screen behaves as
described above, and a window that macOS tiles into an edge on the ultrawide is pushed back into
the channel like any other free window.

### Guards

Nothing moves while the mouse button is down, so dragging a window is never fought mid-drag. A
window that keeps moving away from where moorings puts it, four times inside ten seconds, is left
alone for a minute and the Console says so. Re-moor now clears those holds. Without
Accessibility permission nothing moves, the menu bar shows a warning sign, and one banner
offers the settings page. moorings says everything in its own banner at the top right of the
main screen, not in macOS notifications, so it needs no notification permission. A banner fades
after five seconds, stays while the pointer is on it, and closes when clicked. Widths that leave less
than a 10% channel fall back to 10 and 45, and a step that would do so is grayed out. While the
layout is frozen, Fill, Tidy, Undo and every window action are grayed out, and the shortcuts do
nothing.

Moorings checks the layout four times a second while windows are moving, opening or changing
focus, and once every two seconds after ten quiet seconds, so an idle desk costs almost nothing.
`pollSeconds`, `activeSeconds` and `idleSeconds` in `M.config` set those times.

### Screens

Moorings acts on the widest display whose aspect ratio is at least `minAspect`. With no such
display attached the layout does nothing, so a laptop screen or a 16:9 monitor is safe. Window
actions still work there, and nothing moves until one is pressed.

### Selftest

The test suites run moorings against a fake Hammerspoon. `moorings selftest` checks the real
thing: it asks the running Hammerspoon to drive moorings against throwaway TextEdit documents
and prints each check. It needs the ultrawide attached, Accessibility granted, TextEdit quit and
one empty slot, and it moves your windows for about 30 seconds, so keep your hands off the mouse.

The run borrows an empty slot for TextEdit, preferring a side no other app uses. It checks that
the anchored window lands in its slot, a second window stays free in the channel, the next window
takes the slot when the first closes, an app with no window frees its side, the open picker is
never held, moving the anchored window releases it and its green button puts it back, Weigh
anchor leaves windows alone and Drop anchor puts them back, and the restart helper is loaded and
current. Afterward it closes the documents, quits TextEdit and puts your slots and anchor back,
even when a check fails or the run stops halfway. If Hammerspoon quits or reloads during a run,
moorings puts them back the next time it starts. A pin you released by hand stays released.

The command exits 1 when any check fails and writes the full result to
`~/Library/Logs/moorings/`. `moorings selftest --control` plants one wrong expectation and exits
0 only when exactly that check fails, which shows the selftest can still catch a failure.
GitHub's macOS runners cannot grant Accessibility, so this runs on a real Mac only.

Before a release, choose Reload so Hammerspoon runs the code being released, run both from the
clone, then cut the release:

```sh
./moorings selftest
./moorings selftest --control
gh release create vX.Y.Z --generate-notes --title "vX.Y.Z: Short Description"
```

## Support

moorings is free and will stay free. If I ever stop maintaining it, I'll archive it, and the code
stays open. Keeping it working as macOS and Hammerspoon change takes time. If you want to support
that work, you can [tip the harbormaster](https://github.com/sponsors/dcadolph) through GitHub
Sponsors.

## License

Apache-2.0. See `LICENSE`.
