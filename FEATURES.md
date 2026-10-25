# What you get

Moorings is a free, native menu bar app for macOS 14 or later, signed and notarized. Everything
here works on any display unless it says ultrawide. The [README](README.md) has the details for
each part.

## Window actions on every display

- Rectangle's keymap out of the box: halves that cycle through 1/2, 2/3 and 1/3, quarters,
  thirds, two thirds, maximize, maximize height, center, larger, smaller, restore, and previous
  and next display. Spectacle's and Magnet's keymaps are one menu choice away, and None starts
  from a blank slate.
- Every other Rectangle action by Rectangle's name: display one to nine, a specified size of
  1680 by 1050 points that you can change, and the side and center-section names, so a Rectangle link or script
  works with `moorings://action?name=`.
- Larger, smaller, double and halve on one axis, each toward the edge you pick.
- Fourths, sixths, eighths, ninths, twelfths, sixteenths, vertical thirds, sixths and eighths,
  corner thirds, almost maximize and center prominently in the Window folder, each ready for a
  key of your choice.
- Your own sizes, as shares of the screen, each with its own shortcut.
- A gap around and between the windows an action places.
- Any action from a link such as `moorings://action?name=left-half`, so a script, a launcher or a
  Stream Deck can run it.
- Extra mouse buttons bound to actions.
- Shortcuts that switch off while an app you name is in front.
- Rectangle's behavior preferences at Rectangle's defaults: repeat presses that cycle sizes,
  traverse or cycle displays, cycle quadrants or switch sides, screen edge gaps, room for the
  Stage Manager strip, Enhanced UI handling, a cursor that follows the window, a hidden menu bar
  icon and display ordering.
- Unsnap restore: dragging a placed window away gives it its earlier size back.
- Double-click a title bar to maximize or restore, with apps you name left alone.
- Chains: a named list of actions that runs one step per press on the same window, stopping on
  the last step or looping back to the first, with its own shortcut, mouse button and menu entry.
- The Moorings menu under the pointer, from a shortcut or a mouse button, without bringing
  Moorings to the front.

## Snap by dragging

- Drag a window to an edge or corner, see a footprint of where it lands, and let go to snap it.
  Normal displays use Rectangle's map.
- On the ultrawide, the strips stand in for the screen edges, and holding Option while dropping a
  window on a strip anchors its app there.
- Settings > Snapping picks the action for each edge and corner, separately for landscape and
  portrait displays, turns areas off, names keys that must be held to snap, and sets the edge
  margins and corner sizes. The strips on the ultrawide keep their own zones.
- The footprint's fill opacity, border width, color, fade and fade time are yours to set, and a
  haptic tap can mark each new zone.

## Organize

- Tile columns, tile rows, tile all or one app, cascade all or one app, cycle stacked windows,
  and reverse.
- Tidy channel lines up the two or three front windows, and Undo tidy puts everything back.

## Workspaces

- Save the slots, widths, heights and the frame of every free window on every display under a
  name, then recall it from the menu, a shortcut or a link.
- Tie a workspace to a set of displays, and plugging into that setup recalls it.

## Anchored apps on an ultrawide

- Up to four apps held at the screen edges, a top and bottom slot on each side, with the open
  middle, the channel, left for everything else.
- Nothing is anchored until you choose an app, so a first start moves no window. On an ultrawide,
  one message says how to anchor the first app.
- Anchor *app* at the top of the menu holds the app you were just using.
- Width and height presets and steppers, with a label that says how wide the channel is.
- Click an anchored window's green button to lift it over the channel at full height, and click
  again to lower it.
- Drag an anchored window away and Moorings lets it go, with a message that says how to bring it
  back.
- An app with a minimum width keeps it, and its strip grows to fit.
- Anchored apps that are not running open in the background at launch.
- A side with nothing anchored gives its space to the channel.

## The channel

- A free window that strays into a strip is pushed back. One that is too wide is narrowed and
  grows back when the channel widens.
- Cast off this window lets one window cover the strips, even an anchored app, until it closes
  or you click again.
- A free window's green button fills the channel, and a second click puts it back. Native
  fullscreen fills the channel instead of covering the anchored apps. Each kind of window has its
  own switch.

## Settings window

- Record shortcuts, edit custom sizes, manage workspaces, bind mouse buttons, and pick the keymap,
  snapping, gap, fullscreen handling and one of twelve themes.
- A Menu tab to pin actions to the top of the Window folder, hide the ones you never use, and
  build chains.
- Export every choice to one JSON file and import it on another Mac.
- Restore defaults resets shortcuts, snapping, appearance and behavior, and keeps your anchored
  apps, sizes and workspaces.

## Out of sight

- One sailboat in the menu bar and no Dock icon.
- Messages appear in a themed banner at the top right, not in macOS notifications, so there is no
  notification permission to grant.
- Launch at login is one menu switch. Opening Moorings while it runs shows the settings window.
- Moorings checks once a day for a new release and offers it at the top of the menu. The offer
  opens the release page, and Homebrew or the zip installs it. Nothing installs on its own.
- Installs with `brew install --cask dcadolph/tap/moorings`, or from the signed and notarized zip
  on each release.
- `moorings://selftest` checks the layout against real TextEdit windows, then puts your slots back.
- The layout is checked four times a second while windows change and every two seconds when
  nothing is moving.
- Nothing moves while the mouse button is down, and a window that keeps fighting its place is
  left alone for a minute.
- Without Accessibility access, a warning sign and one banner lead to the right settings page.
- Tip the harbormaster, below a separator just above Quit Moorings, opens the GitHub Sponsors
  page. Nothing asks for a tip.
