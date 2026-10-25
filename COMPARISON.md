# How Moorings compares

Every row names its check. A row reads yes only when that check passes. Rows that read planned point to the unit of work that will add the feature and its check, and the table changes as units land. A no row gives its reason. Prices come from each product page as read on 2026-10-24, and where a page gave no price the row says so.

## Rectangle Pro

Price is not on the product page. A 2022 article gave 10 EUR. It has a 10-day trial and covers 3 devices. Charmstone, its separate app switcher, is out of scope because it is not a window manager.

| Feature                                                | Who has it    | Moorings                                                        | Check                                                                                  |
|--------------------------------------------------------|---------------|-----------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Window throw, 16 sizes, works on an unfocused window   | Rectangle Pro | yes, by a held key, on the window under the pointer             | testOverlayPick, testOverlayTargetsKnown, testOverlayTriggerHeld; live check owed      |
| Quick throw and throw by cursor direction              | Rectangle Pro | yes, by cursor direction                                        | testOverlayPick; live check owed                                                       |
| Custom snap targets and a configurable snap panel      | Rectangle Pro | yes, custom areas off the ultrawide and a snap panel on a pause | testSnapCustomAreas, testSnapPanelLayout, testSnapChoicesCustomDecode; live check owed |
| Custom sizes with repeat behavior                      | Rectangle Pro | yes                                                             | testCustomSize, testSizeShortcuts                                                      |
| Workspace arrangement by shortcut                      | Rectangle Pro | yes                                                             | testWorkspacesMatch, testWorkspacesFitAndCodable                                       |
| Workspace arrangement on display connect or disconnect | Rectangle Pro | yes                                                             | testWorkspacesSignature                                                                |
| Stash at a screen edge with slide-out on hover         | Rectangle Pro | yes, left, right and bottom edges, no top edge                  | testStashFrames, testStashHover, testStashEdges, testStashedStaysPut; live check owed  |
| Pin one app to a side                                  | Rectangle Pro | yes                                                             | selftest "anchored window lands in its slot"                                           |
| Todo mode with more settings                           | Rectangle Pro | no (anchored apps cover the pinning, no separate mode)          | not applicable                                                                         |
| Menu customization, by shortcut or as a context menu   | Rectangle Pro | yes                                                             | testMenuVisible, testMenuPinned, live 10-24                                            |
| Import from Rectangle, export file or live settings    | Rectangle Pro | yes                                                             | testRectangleImportRoundTrip, testRectangleImportLive                                  |
| iCloud sync                                            | Rectangle Pro | planned (unit 20)                                               | unit 20 settings sync on iCloud                                                        |
| Windows-style arrow keys and left/right fill           | Rectangle Pro | yes                                                             | testArrowWalk, testFillLeftStops, testWindowsKeymap                                    |

## Rectangle

Rectangle is free and MIT licensed. The action list and the hidden preferences come from its TerminalCommands.md.

| Feature                                                                                                                                                                                                                                                                        | Who has it                 | Moorings          | Check                                                                                             |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------|-------------------|---------------------------------------------------------------------------------------------------|
| Halves, quarters, thirds, two thirds, fourths, sixths, eighths                                                                                                                                                                                                                 | Rectangle, Raycast, Magnet | yes               | testAllNames, testRectangleDefaults                                                               |
| Vertical thirds, twelfths, sixteenths                                                                                                                                                                                                                                          | Rectangle, Raycast         | yes               | testFinerGrids, testFinerCover                                                                    |
| Maximize, almost maximize, maximize height, center                                                                                                                                                                                                                             | Rectangle, Raycast         | yes               | testAllNames                                                                                      |
| Center half                                                                                                                                                                                                                                                                    | Rectangle, Raycast         | yes               | testAllNames                                                                                      |
| Larger and smaller                                                                                                                                                                                                                                                             | Rectangle, Raycast         | yes               | testLargerSmaller                                                                                 |
| Larger and smaller on one axis, double and halve width and height                                                                                                                                                                                                              | Rectangle, Raycast         | yes               | testAxisActions, testAllNames                                                                     |
| Specified size, sides and center section, move to display 1 to 9                                                                                                                                                                                                               | Rectangle, Raycast         | yes               | testSpecified, testSideAliases, testSpecificDisplay                                               |
| Move to edges                                                                                                                                                                                                                                                                  | Rectangle                  | yes               | testAllNames                                                                                      |
| Next and previous display                                                                                                                                                                                                                                                      | Rectangle, Raycast         | yes               | testDisplayMove                                                                                   |
| Restore                                                                                                                                                                                                                                                                        | Rectangle, Raycast         | planned (unit 26) | unit 26 undo history                                                                              |
| Tile and cascade                                                                                                                                                                                                                                                               | Rectangle                  | yes               | testTileCascade, testTileColumnsRows                                                              |
| Gaps                                                                                                                                                                                                                                                                           | Rectangle                  | yes               | testActionGap, testGap                                                                            |
| Subsequent execution cycle or traverse                                                                                                                                                                                                                                         | Rectangle                  | yes               | testTraverse, testTraverseAndCycle, testSwitchSidesAndNone, testCycleQuadrants, testCycleDisplays |
| Repeated maximize restores                                                                                                                                                                                                                                                     | Rectangle                  | yes               | testRestoresMaximize                                                                              |
| Center half cycles                                                                                                                                                                                                                                                             | Rectangle                  | yes               | testCenterHalfCycles                                                                              |
| Halves preserve the other axis                                                                                                                                                                                                                                                 | Rectangle                  | yes               | testHalvesPreserveOtherAxis                                                                       |
| Minimum window size                                                                                                                                                                                                                                                            | Rectangle                  | yes               | testMinimumWindowSize                                                                             |
| Stack badge with the count of stacked windows, on a rest at the corner                                                                                                                                                                                                         | Rectangle                  | yes               | testStack, testStackDensest, testHovered, shared with cycling                                     |
| Screen edge gaps and notch, gaps on main display only, gaps on maximize                                                                                                                                                                                                        | Rectangle                  | yes               | testEdgeGaps                                                                                      |
| Unsnap restore                                                                                                                                                                                                                                                                 | Rectangle                  | yes               | testSnapped, testUnsnapFrame, testUnsnapSize                                                      |
| Double-click title bar                                                                                                                                                                                                                                                         | Rectangle                  | yes               | testOnTitleBar, testTitleBarAction                                                                |
| Move cursor with window, enhanced UI handling, Stage Manager size                                                                                                                                                                                                              | Rectangle                  | yes               | testEnhancedUIPolicy, testStage, behavior.moveCursor                                              |
| Hide menu bar icon, screens ordered by x                                                                                                                                                                                                                                       | Rectangle                  | yes               | testOrderRows, behavior.hideMenuBarIcon                                                           |
| Snap area configuration, ignored areas, snap modifiers, margins                                                                                                                                                                                                                | Rectangle                  | yes               | testSnapCustomMapAndIgnoredArea, testSnapModifiersGate, testSnapMarginsAndSizes                   |
| Footprint style                                                                                                                                                                                                                                                                | Rectangle                  | yes               | testFootprintStyleTints, testFootprintStyleFadeTime                                               |
| Drag to an edge or corner with a footprint                                                                                                                                                                                                                                     | Rectangle, Magnet          | yes               | testSnapEdges, testThemeFootprint                                                                 |
| Other hidden preferences (resizeOnDirectionalMove, centeredDirectionalMove, sizeOffset, curtainChangeSize, smallerShrinksMaximizedHeight, autoMaximize, attemptMatchOnNextPrevDisplay, moveFixedSizeToEdge, directAnimationNativeResizeApps, almost maximize width and height) | Rectangle                  | planned (unit 6)  | unit 6 behavior choices                                                                           |

## Moom

Moom costs $15.

| Feature                                                  | Who has it                  | Moorings                                                                           | Check                                  |
| -------------------------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------- |
| Pop-up palette on the green button with up to 61 actions | Moom                        | yes, as a menu at the pointer by shortcut or mouse button, not on the green button | live 10-24                             |
| Saved layouts for an app's windows and recent windows    | Moom                        | yes                                                                                | testWorkspacesFitAndCodable            |
| Snap zones                                               | Moom                        | yes                                                                                | testSnapEdges                          |
| Drop zones from a saved layout                           | Moom                        | partial: custom areas drawn as shares, not made from a saved layout                | testSnapCustomAreas                    |
| Chains of actions, in sequence or looped                 | Moom                        | yes                                                                                | testChainStepStops, testChainStepLoops |
| Hover move and resize with modifiers, no click           | Moom, Lasso                 | planned (unit 21)                                                                  | unit 21 hover move and resize          |
| Keyboard grid controller                                 | Moom                        | yes, arrows under the held key, Return applies                                     | testOverlayGrid; live check owed       |
| Folders in the menu                                      | Moom                        | no (fixed folders by family; actions are pinned or hidden instead)                 | not applicable                         |
| Per-action grid sizes                                    | Moom                        | planned (unit 21)                                                                  | unit 21 grid overlay                   |
| Use active window size                                   | Moom                        | planned (unit 5)                                                                   | unit 5 specified size                  |
| Display adjustment of layouts                            | Moom                        | yes                                                                                | testWorkspacesFitAndCodable            |
| Dock, menu bar or invisible app modes                    | Moom                        | no (menu bar only by design)                                                       | not applicable                         |
| Modifier drag to move or resize from anywhere            | Moom, BetterSnapTool, Lasso | planned (unit 21)                                                                  | unit 21 hover move and resize          |

## BetterSnapTool

It is sold on the Mac App Store. The price is not on the page.

| Feature                                         | Who has it             | Moorings               | Check                                |
|-------------------------------------------------|------------------------|------------------------|--------------------------------------|
| Corner and edge snapping                        | BetterSnapTool, Magnet | yes                    | testSnapEdges                        |
| Custom snap areas anywhere                      | BetterSnapTool         | yes, off the ultrawide | testSnapCustomAreas; live check owed |
| Custom shortcuts                                | BetterSnapTool         | yes                    | testSizeShortcuts                    |
| Green button lifts or fills instead of zoom     | BetterSnapTool         | yes                    | testLiftGreenButton                  |
| Customized clicks on the red and yellow buttons | BetterSnapTool         | yes                    | testButtonClicksAction               |
| Move or resize while holding a key              | BetterSnapTool         | planned (unit 21)      | unit 21 hover move and resize        |

## Loop

Loop is free and GPL-3 licensed.

| Feature                        | Who has it | Moorings                                                                             | Check                                                    |
| ------------------------------ | ---------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| Radial menu on a trigger key   | Loop       | yes, 16 targets in two rings                                                         | testOverlayPick, testOverlayTriggerHeld; live check owed |
| Preview outline while choosing | Loop       | yes, the snap footprint                                                              | live check owed                                          |
| Trigger-key chords             | Loop       | partial: arrows, Shift-arrows, Return and Escape under the trigger; no custom chords | testOverlayTriggerHeld; live check owed                  |
| Cycles                         | Loop       | yes                                                                                  | testCycle, testPressCycle                                |
| Stash                          | Loop       | yes, left, right and bottom edges                                                    | testStashFrames, testStashHover; live check owed         |
| Theming                        | Loop       | yes                                                                                  | testThemeList, testThemeContrast                         |

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

| Feature                                                           | Who has it     | Moorings                          | Check                |
|-------------------------------------------------------------------|----------------|-----------------------------------|----------------------|
| Create and destroy Space                                          | yabai          | no (needs SIP off)                | not applicable       |
| Shadows, transparency, layers, sticky windows, picture in picture | yabai          | no (needs SIP off)                | not applicable       |
| Window animations                                                 | yabai          | yes, off by default, experimental | testAnimationSteps   |
| Scratchpads                                                       | yabai          | no (needs SIP off)                | not applicable       |
| Move a window to another Space with SIP on                        | yabai, Raycast | planned (unit 24 spike)           | unit 24 spaces spike |

## Magnet

Magnet is sold on the Mac App Store. Nothing here goes past Rectangle.

| Feature                  | Who has it | Moorings | Check           |
| ------------------------ | ---------- | -------- | --------------- |
| Drag snapping            | Magnet     | yes      | testSnapEdges   |
| Halves, quarters, thirds | Magnet     | yes      | testAllNames    |
| Several displays         | Magnet     | yes      | testDisplayMove |

## Divvy, Mosaic and Lasso

Divvy costs $13.99 and Mosaic 14.99 GBP. The Lasso price is on a separate page and it covers 3 devices.

| Feature                                 | Who has it           | Moorings                                                                            | Check                               |
|-----------------------------------------|----------------------|-------------------------------------------------------------------------------------|-------------------------------------|
| Drag over a grid to pick a span         | Divvy, Mosaic, Lasso | planned (unit 21)                                                                   | unit 21 grid overlay drag           |
| Quick positions without resizing        | Mosaic               | planned (unit 21)                                                                   | unit 21 quick positions             |
| Auto layout per app window              | Mosaic               | planned (unit 17)                                                                   | unit 17 per-app rules               |
| Groups of layouts, switchable profiles  | Mosaic               | yes                                                                                 | testProfileApplyTouchesOnlySettings |
| Touch Bar                               | Mosaic               | no (Apple dropped the Touch Bar from current Macs)                                  | not applicable                      |
| Window capture, iOS remote control      | Mosaic               | no (no unit yet, see the plan's Escalations)                                        | not applicable                      |
| Saved layouts with per-layout shortcuts | Lasso                | yes                                                                                 | testWorkspacesFitAndCodable         |
| iCloud sync                             | Lasso                | planned (unit 20)                                                                   | unit 20 settings sync on iCloud     |
| Export and import                       | Lasso                | yes                                                                                 | testSettingsBackupRoundTrip         |
| Rectangle keymap preset                 | Lasso                | yes                                                                                 | testRectangleDefaults               |
| Magnet keymap preset                    | Lasso                | yes (Magnet's site lists no shortcuts; the table is the Magnet set Rectangle ships) | testMagnet                          |

## Raycast window management

| Feature                                                | Who has it | Moorings                      | Check                          |
| ------------------------------------------------------ | ---------- | ----------------------------- | ------------------------------ |
| Rectangle action set                                   | Raycast    | yes (see the Rectangle table) | testAllNames                   |
| Move to Previous or Next Space, Move to Desktop 1 to 9 | Raycast    | planned (unit 24 spike)       | unit 24 spaces spike           |
| Rename Desktop                                         | Raycast    | no (macOS has no public call to name a Space) | not applicable |
| Close a window                                         | Raycast    | yes (close-window)            | testKnown                      |
| Open a window                                          | Raycast    | no (a new window is an app command; launching an app is covered by workspaces) | not applicable |
| Focus next or previous app window                      | Raycast    | yes (focus-next-window, focus-previous-window) | testTileNeighbor, selftest focus case |
| Exact size and position commands in points             | Raycast    | yes                           | testPointsSpec, testSpecified|
| Size and position as shares of the screen              | Raycast    | yes                           | testCustomShare                |
| Layouts of up to eight windows with launch arguments   | Raycast    | planned (unit 17)             | unit 17 layouts that open apps |
| Other windows behavior (minimize or close others)      | Raycast    | yes (minimize-others, close-others; anchored windows stay) | testKnown |
| Deeplinks                                              | Raycast    | planned (unit 26)             | unit 26 App Intents and links  |

## Energy

Measured with mac/scripts/energy.sh on an M1 Max, macOS 26.6.1. Idle means no window moving. Churn means the app itself moves a TextEdit window between halves every two seconds through its own links (`energy.sh -c`), so the work measured is the app's. Each app runs alone on the same Mac. The protocol is ten minutes per cell. The Moorings cells below came from shorter runs and say so. The Rectangle and Loop cells wait for a sitting with both installed.

| Measure                   | Moorings                     | Rectangle | Loop |
| ------------------------- | ---------------------------- | --------- | ---- |
| Idle mean CPU percent     | 0.98 (1 min, 2026-10-25)     |           |      |
| Idle energy impact        | 0.98 (1 min, 2026-10-25)     |           |      |
| Churn mean CPU percent    | 8.88 (2 min, 2026-10-25)     |           |      |
| Churn energy impact       | 8.88 (2 min, 2026-10-25)     |           |      |

For Moorings, top's energy impact equals its CPU percent in every sample. The window animation switch (Settings > Behavior) changed churn from 8.88 off to 8.68 on in the same two-minute protocol, which is inside the run-to-run spread. With the stack badge on and showing, idle read 1.12.

## What only Moorings has

None of the products above hold apps at the edges of an ultrawide with a channel between them.

| Feature                                     | Who has it | Moorings | Check                                                                 |
| ------------------------------------------- | ---------- | -------- | --------------------------------------------------------------------- |
| Anchored apps in edge slots on an ultrawide | Moorings   | yes      | selftest "anchored window lands in its slot"                          |
| Channel with push back for free windows     | Moorings   | yes      | testPushAndShrink, selftest "second window stays free in the channel" |
| Lift an anchored window over the channel    | Moorings   | yes      | testLiftLiftsAndLowers                                                |
| Cast off a window over the strips           | Moorings   | yes      | testCastOffStaysPut                                                   |
| Drag release of an anchored window          | Moorings   | yes      | selftest "dragging the anchored window by its title bar releases it"  |
