# What you get

Moorings is free and runs inside [Hammerspoon](https://www.hammerspoon.org). Everything here works
on any display unless it says ultrawide. The [README](README.md) has the details for each part.

## Window actions on every display

- Rectangle's keymap out of the box: halves that cycle through 1/2, 2/3 and 1/3, quarters,
  thirds, two thirds, maximize, maximize height, center, larger, smaller, restore, and previous
  and next display. Spectacle's keymap is one menu choice away.
- Fourths, sixths, eighths, ninths, corner thirds, almost maximize and center prominently in the
  Window folder, each ready for a key of your choice.
- Your own sizes, as shares of the screen or in points, each with its own shortcut.
- A gap around and between the windows an action places.
- Any action from a link such as `hammerspoon://moorings?action=left-half`, so a script, a
  launcher or a Stream Deck can run it.
- Extra mouse buttons bound to actions.
- Shortcuts that switch off while an app you name is in front.

## Snap by dragging

- Drag a window to an edge or corner, see a footprint of where it lands, and let go to snap it.
  Normal displays use Rectangle's map.
- On the ultrawide, the strips stand in for the screen edges, and holding Option while dropping a
  window on a strip anchors its app there.

## Organize

- Tile columns, tile rows, tile all, cascade all or one app, cycle stacked windows, and reverse.
- Tidy channel lines up the two or three front windows, and Undo tidy puts everything back.

## Workspaces

- Save the slots, widths, heights and the frame of every free window on every display under a
  name, then recall it from the menu, a shortcut or a link.
- Tie a workspace to a set of displays, and plugging into that setup recalls it.

## Anchored apps on an ultrawide

- Up to four apps held at the screen edges, a top and bottom slot on each side, with the open
  middle, the channel, left for everything else.
- Anchor *app* at the top of the menu holds the app you were just using.
- Width and height presets and steppers, with a label that says how wide the channel is.
- Click an anchored window's green button to lift it over the channel at full height, and click
  again to lower it.
- Drag an anchored window away and moorings lets it go, with a message that says how to bring it
  back.
- An app with a minimum width keeps it, and its strip grows to fit.
- Anchored apps that are not running open in the background at login.
- A side with nothing anchored gives its space to the channel.

## The channel

- A free window that strays into a strip is pushed back. One that is too wide is narrowed and
  grows back when the channel widens.
- A free window's green button fills the channel, and a second click puts it back. Native
  fullscreen fills the channel instead of covering the anchored apps. Each kind of window has its
  own switch.

## Settings window

- Record shortcuts, edit custom sizes, manage workspaces, and pick the icon, keymap, snapping and
  gap without touching the Lua file.

## Out of sight

- One mark in the menu bar. Hammerspoon's own menu bar and Dock icons stay hidden.
- Messages appear in a moorings banner at the top right, not in macOS notifications, so there is
  no notification permission to grant.
- Hammerspoon starts at login, installs its own updates quietly, and starts again within 30
  seconds if it quits or crashes. Quit moorings stops all of it until the next login.
- The layout is checked four times a second while windows change and every two seconds when
  nothing is moving.
- Nothing moves while the mouse button is down, and a window that keeps fighting its place is
  left alone for a minute.
- Without Accessibility access, a warning sign and one banner lead to the right settings page.
- Reload refuses a config with an error, so a typo cannot stop the layout.
