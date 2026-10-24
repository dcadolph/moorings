# How Moorings compares

Every row names its check. A row reads yes only when that check passes. Rows that read planned point to the unit of work that will add the feature and its check, and the table changes as units land. A no row gives its reason. Prices come from each product page as read on 2026-10-24, and where a page gave no price the row says so.

## Rectangle Pro

Price is not on the product page. A 2022 article gave 10 EUR. It has a 10-day trial and covers 3 devices. Charmstone, its separate app switcher, is out of scope because it is not a window manager.

| Feature                                                | Who has it    | Moorings                                               | Check                                            |
| ------------------------------------------------------ | ------------- | ------------------------------------------------------ | ------------------------------------------------ |
| Window throw, 16 sizes, works on an unfocused window   | Rectangle Pro | planned (unit 14)                                      | unit 14 trigger-key overlay                      |
| Quick throw and throw by cursor direction              | Rectangle Pro | planned (unit 14)                                      | unit 14 trigger-key overlay                      |
| Custom snap targets and a configurable snap panel      | Rectangle Pro | planned (unit 16)                                      | unit 16 snap panel                               |
| Custom sizes with repeat behavior                      | Rectangle Pro | yes                                                    | testCustomSize, testSizeShortcuts                |
| Workspace arrangement by shortcut                      | Rectangle Pro | yes                                                    | testWorkspacesMatch, testWorkspacesFitAndCodable |
| Workspace arrangement on display connect or disconnect | Rectangle Pro | yes                                                    | testWorkspacesSignature                          |
| Stash at a screen edge with slide-out on hover         | Rectangle Pro | planned (unit 15)                                      | unit 15 stash                                    |
| Pin one app to a side                                  | Rectangle Pro | yes                                                    | selftest "anchored window lands in its slot"     |
| Todo mode with more settings                           | Rectangle Pro | no (anchored apps cover the pinning, no separate mode) | not applicable                                   |
| Menu customization, by shortcut or as a context menu   | Rectangle Pro | planned (unit 13)                                      | unit 13 menu by shortcut and context menu        |
| Import from Rectangle                                  | Rectangle Pro | no (no unit yet, see the plan's Escalations)           | not applicable                                   |
| iCloud sync                                            | Rectangle Pro | planned (unit 20)                                      | unit 20 settings sync on iCloud                  |
| Windows-style arrow keys and left/right fill           | Rectangle Pro | no (no unit yet, see the plan's Escalations)           | not applicable                                   |

## Rectangle

Rectangle is free and MIT licensed. The action list and the hidden preferences come from its TerminalCommands.md.

| Feature                                                                                                                                                                                                                                                                        | Who has it                 | Moorings          | Check                                     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------- | ----------------- | ----------------------------------------- |
| Halves, quarters, thirds, two thirds, fourths, sixths, eighths                                                                                                                                                                                                                 | Rectangle, Raycast, Magnet | yes               | testAllNames, testRectangleDefaults       |
| Vertical thirds, twelfths, sixteenths                                                                                                                                                                                                                                          | Rectangle, Raycast         | yes               | testFinerGrids, testFinerCover            |
| Maximize, almost maximize, maximize height, center                                                                                                                                                                                                                             | Rectangle, Raycast         | yes               | testAllNames                              |
| Center half                                                                                                                                                                                                                                                                    | Rectangle, Raycast         | yes               | testAllNames                              |
| Larger and smaller                                                                                                                                                                                                                                                             | Rectangle, Raycast         | yes               | testLargerSmaller                         |
| Larger and smaller on one axis, double and halve width and height                                                                                                                                                                                                              | Rectangle, Raycast         | yes               | testAxisActions, testAllNames             |
| Specified size, sides and center section, move to display 1 to 9                                                                                                                                                                                                                | Rectangle, Raycast         | planned (unit 5)  | unit 5 specified size                     |
| Move to edges                                                                                                                                                                                                                                                                  | Rectangle                  | yes               | testAllNames                              |
| Next and previous display                                                                                                                                                                                                                                                      | Rectangle, Raycast         | yes               | testDisplayMove                           |
| Restore                                                                                                                                                                                                                                                                        | Rectangle, Raycast         | planned (unit 26) | unit 26 undo history                      |
| Tile and cascade                                                                                                                                                                                                                                                               | Rectangle                  | yes               | testTileCascade, testTileColumnsRows      |
| Gaps                                                                                                                                                                                                                                                                           | Rectangle                  | yes               | testActionGap, testGap                    |
| Subsequent execution cycle or traverse                                                                                                                                                                                                                                         | Rectangle                  | planned (unit 6)  | unit 6 behavior choices                   |
| Repeated maximize restores                                                                                                                                                                                                                                                     | Rectangle                  | planned (unit 6)  | unit 6 repeatedMaximizeRestores           |
| Center half cycles                                                                                                                                                                                                                                                             | Rectangle                  | planned (unit 6)  | unit 6 centerHalfCycles                   |
| Halves preserve the other axis                                                                                                                                                                                                                                                 | Rectangle                  | planned (unit 6)  | unit 6 halvesPreserveOtherAxis            |
| Minimum window size                                                                                                                                                                                                                                                            | Rectangle                  | planned (unit 6)  | unit 6 behavior choices                   |
| Screen edge gaps and notch, gaps on main display only, gaps on maximize                                                                                                                                                                                                        | Rectangle                  | planned (unit 6)  | unit 6 gap settings                       |
| Unsnap restore                                                                                                                                                                                                                                                                 | Rectangle                  | planned (unit 8)  | unit 8 unsnapRestore                      |
| Double-click title bar                                                                                                                                                                                                                                                         | Rectangle                  | planned (unit 8)  | unit 8 doubleClickTitleBar                |
| Move cursor with window, enhanced UI handling, Stage Manager size                                                                                                                                                                                                              | Rectangle                  | planned (unit 7)  | unit 7 moveCursor, enhancedUI, stageSize  |
| Hide menu bar icon, screens ordered by x                                                                                                                                                                                                                                       | Rectangle                  | planned (unit 7)  | unit 7 hideMenuBarIcon, screensOrderedByX |
| Snap area configuration, ignored areas, snap modifiers, margins                                                                                                                                                                                                                | Rectangle                  | planned (unit 9)  | unit 9 drag snap configuration            |
| Footprint style                                                                                                                                                                                                                                                                | Rectangle                  | planned (unit 9)  | unit 9 footprint style                    |
| Drag to an edge or corner with a footprint                                                                                                                                                                                                                                     | Rectangle, Magnet          | yes               | testSnapEdges, testThemeFootprint         |
| Other hidden preferences (resizeOnDirectionalMove, centeredDirectionalMove, sizeOffset, curtainChangeSize, smallerShrinksMaximizedHeight, autoMaximize, attemptMatchOnNextPrevDisplay, moveFixedSizeToEdge, directAnimationNativeResizeApps, almost maximize width and height) | Rectangle                  | planned (unit 6)  | unit 6 behavior choices                   |

## Moom

Moom costs $15.

| Feature                                                  | Who has it                  | Moorings                                                            | Check                         |
| -------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------- | ----------------------------- |
| Pop-up palette on the green button with up to 61 actions | Moom                        | planned (unit 13) as a menu at the cursor, not on the green button  | unit 13 context menu          |
| Saved layouts for an app's windows and recent windows    | Moom                        | yes                                                                 | testWorkspacesFitAndCodable   |
| Snap zones                                               | Moom                        | yes                                                                 | testSnapEdges                 |
| Drop zones from a saved layout                           | Moom                        | planned (unit 16)                                                   | unit 16 custom snap areas     |
| Chains of actions, in sequence or looped                 | Moom                        | planned (unit 12)                                                   | unit 12 chains                |
| Hover move and resize with modifiers, no click           | Moom, Lasso                 | planned (unit 21)                                                   | unit 21 hover move and resize |
| Keyboard grid controller                                 | Moom                        | planned (unit 14)                                                   | unit 14 keyboard grid         |
| Folders in the menu                                      | Moom                        | planned (unit 12)                                                   | unit 12 menu customization    |
| Per-action grid sizes                                    | Moom                        | planned (unit 21)                                                   | unit 21 grid overlay          |
| Use active window size                                   | Moom                        | planned (unit 5)                                                    | unit 5 specified size         |
| Display adjustment of layouts                            | Moom                        | yes                                                                 | testWorkspacesFitAndCodable   |
| Dock, menu bar or invisible app modes                    | Moom                        | no (menu bar only by design)                                        | not applicable                |
| Modifier drag to move or resize from anywhere            | Moom, BetterSnapTool, Lasso | planned (unit 21)                                                   | unit 21 hover move and resize |

## BetterSnapTool

It is sold on the Mac App Store. The price is not on the page.

| Feature                                       | Who has it             | Moorings                             | Check                         |
| --------------------------------------------- | ---------------------- | ------------------------------------ | ----------------------------- |
| Corner and edge snapping                      | BetterSnapTool, Magnet | yes                                  | testSnapEdges                 |
| Custom snap areas anywhere                    | BetterSnapTool         | planned (unit 16)                    | unit 16 custom snap areas     |
| Custom shortcuts                              | BetterSnapTool         | yes                                  | testSizeShortcuts             |
| Green button lifts or fills instead of zoom   | BetterSnapTool         | yes                                  | testLiftGreenButton           |
| Customized clicks on the red and yellow buttons | BetterSnapTool       | no (no unit yet, see the plan's Escalations) | not applicable        |
| Move or resize while holding a key            | BetterSnapTool         | planned (unit 21)                    | unit 21 hover move and resize |

## Loop

Loop is free and GPL-3 licensed.

| Feature                        | Who has it | Moorings          | Check                            |
| ------------------------------ | ---------- | ----------------- | -------------------------------- |
| Radial menu on a trigger key   | Loop       | planned (unit 14) | unit 14 radial menu              |
| Preview outline while choosing | Loop       | planned (unit 14) | unit 14 radial menu              |
| Trigger-key chords             | Loop       | planned (unit 14) | unit 14 radial menu              |
| Cycles                         | Loop       | yes               | testCycle, testPressCycle        |
| Stash                          | Loop       | planned (unit 15) | unit 15 stash                    |
| Theming                        | Loop       | yes               | testThemeList, testThemeContrast |

## Swish

Swish costs $16.

| Feature                                                                      | Who has it | Moorings                                    | Check                      |
| ---------------------------------------------------------------------------- | ---------- | ------------------------------------------- | -------------------------- |
| 30 trackpad gestures on title bars, Dock and menu bar                        | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Grid snapping by swipe, pinch to close or fullscreen, swipe down to minimize | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Spaces by gesture                                                            | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Divider drag that resizes several windows at once                            | Swish      | planned (unit 26)                           | unit 26 shared-edge resize |

## Stay

| Feature                              | Who has it | Moorings          | Check                            |
| ------------------------------------ | ---------- | ----------------- | -------------------------------- |
| Window positions per set of displays | Stay       | yes               | testWorkspacesSignature          |
| Restore on display change            | Stay       | yes               | testWorkspacesMatch              |
| Automatic capture with no save step  | Stay       | planned (unit 17) | unit 17 recall on display change |

## Amethyst

Amethyst is free and MIT licensed.

| Feature                                                                              | Who has it | Moorings            | Check                       |
| ------------------------------------------------------------------------------------ | ---------- | ------------------- | --------------------------- |
| Layouts tall, tall-right, wide, two pane, 3column, widescreen-tall, column, row, BSP | Amethyst   | planned (unit 23)   | unit 23 auto tiling mode    |
| Fullscreen and floating layouts                                                      | Amethyst   | planned (unit 23)   | unit 23 auto tiling mode    |
| Custom JS layouts                                                                    | Amethyst   | no (no unit yet, see the plan's Escalations) | not applicable |
| Focus and swap by direction, layout cycling                                          | Amethyst   | planned (unit 23)   | unit 23 focus and swap      |
| Per-space layouts                                                                    | Amethyst   | planned (unit 24)   | unit 24 spaces spike        |
| YAML config                                                                          | Amethyst   | yes (one JSON file) | testSettingsBackupRoundTrip |

## yabai

yabai is free. Its scripting-addition features need System Integrity Protection partly off. Moorings keeps it on.

| Feature                                                           | Who has it     | Moorings                          | Check                  |
| ----------------------------------------------------------------- | -------------- | --------------------------------- | ---------------------- |
| Create and destroy Space                                          | yabai          | no (needs SIP off)                | not applicable         |
| Shadows, transparency, layers, sticky windows, picture in picture | yabai          | no (needs SIP off)                | not applicable         |
| Window animations                                                 | yabai          | no (no unit yet, see the plan's Escalations) | not applicable |
| Scratchpads                                                       | yabai          | no (needs SIP off)                | not applicable         |
| Move a window to another Space with SIP on                        | yabai, Raycast | planned (unit 24 spike)           | unit 24 spaces spike   |

## Magnet

Magnet is sold on the Mac App Store. Nothing here goes past Rectangle.

| Feature                  | Who has it | Moorings | Check           |
| ------------------------ | ---------- | -------- | --------------- |
| Drag snapping            | Magnet     | yes      | testSnapEdges   |
| Halves, quarters, thirds | Magnet     | yes      | testAllNames    |
| Several displays         | Magnet     | yes      | testDisplayMove |

## Divvy, Mosaic and Lasso

Divvy costs $13.99 and Mosaic 14.99 GBP. The Lasso price is on a separate page and it covers 3 devices.

| Feature                                       | Who has it           | Moorings          | Check                           |
| --------------------------------------------- | -------------------- | ----------------- | ------------------------------- |
| Drag over a grid to pick a span               | Divvy, Mosaic, Lasso | planned (unit 21) | unit 21 grid overlay drag       |
| Quick positions without resizing              | Mosaic               | planned (unit 21) | unit 21 quick positions         |
| Auto layout per app window                    | Mosaic               | planned (unit 17) | unit 17 per-app rules           |
| Groups of layouts                             | Mosaic               | no (no unit yet, see the plan's Escalations) | not applicable |
| Touch Bar                                     | Mosaic               | no (Apple dropped the Touch Bar from current Macs) | not applicable |
| Window capture, iOS remote control            | Mosaic               | no (no unit yet, see the plan's Escalations) | not applicable |
| Saved layouts with per-layout shortcuts       | Lasso                | yes               | testWorkspacesFitAndCodable     |
| iCloud sync                                   | Lasso                | planned (unit 20) | unit 20 settings sync on iCloud |
| Export and import                             | Lasso                | yes               | testSettingsBackupRoundTrip     |
| Rectangle keymap preset                       | Lasso                | yes               | testRectangleDefaults           |
| Magnet keymap preset                          | Lasso                | no (no unit yet, see the plan's Escalations) | not applicable |

## Raycast window management

| Feature                                                | Who has it | Moorings                      | Check                          |
| ------------------------------------------------------ | ---------- | ----------------------------- | ------------------------------ |
| Rectangle action set                                   | Raycast    | yes (see the Rectangle table) | testAllNames                   |
| Move to Previous or Next Space, Move to Desktop 1 to 9 | Raycast    | planned (unit 24 spike)       | unit 24 spaces spike           |
| Rename Desktop                                         | Raycast    | no (macOS has no public call to name a Space) | not applicable |
| Open and Close a window                                | Raycast    | no (no unit yet, see the plan's Escalations) | not applicable  |
| Focus next or previous app window                      | Raycast    | no (no unit yet, see the plan's Escalations) | not applicable  |
| Exact size and position commands in points             | Raycast    | planned (unit 5)              | unit 5 specified size          |
| Size and position as shares of the screen              | Raycast    | yes                           | testCustomShare                |
| Layouts of up to eight windows with launch arguments   | Raycast    | planned (unit 17)             | unit 17 layouts that open apps |
| Other windows behavior (minimize or close others)      | Raycast    | no (no unit yet, see the plan's Escalations) | not applicable  |
| Deeplinks                                              | Raycast    | planned (unit 26)             | unit 26 App Intents and links  |

## Energy

Cells stay empty until unit 2 measures them with mac/scripts/energy.sh. Idle means ten minutes with no window moving. Churn means ten minutes with a window moved every two seconds. Each app runs alone on the same Mac.

| Measure                   | Moorings | Rectangle | Loop |
| ------------------------- | -------- | --------- | ---- |
| Idle mean CPU percent     |          |           |      |
| Idle energy impact        |          |           |      |
| Churn mean CPU percent    |          |           |      |
| Churn energy impact       |          |           |      |

## What only Moorings has

None of the products above hold apps at the edges of an ultrawide with a channel between them.

| Feature                                     | Who has it | Moorings | Check                                                                 |
| ------------------------------------------- | ---------- | -------- | --------------------------------------------------------------------- |
| Anchored apps in edge slots on an ultrawide | Moorings   | yes      | selftest "anchored window lands in its slot"                          |
| Channel with push back for free windows     | Moorings   | yes      | testPushAndShrink, selftest "second window stays free in the channel" |
| Lift an anchored window over the channel    | Moorings   | yes      | testLiftLiftsAndLowers                                                |
| Cast off a window over the strips           | Moorings   | yes      | testCastOffStaysPut                                                   |
| Drag release of an anchored window          | Moorings   | yes      | selftest "dragging the anchored window by its title bar releases it"  |
