# How Moorings compares

Every row names its check. A row reads yes only when that check passes. Rows that read planned point to the unit of work that will add the feature and its check, and the table changes as units land. A no row gives its reason. Prices come from each product page as read on 2026-10-24, and where a page gave no price the row says so.

## Rectangle Pro

Price is not on the product page. A 2022 article gave 10 EUR. It has a 10-day trial and covers 3 devices. Charmstone, its separate app switcher, is out of scope because it is not a window manager.

| Feature                                                | Who has it    | Moorings                                                        | Check                                                                                                                    |
|--------------------------------------------------------|---------------|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| Window throw, 16 sizes, works on an unfocused window   | Rectangle Pro | yes, by a held key, on the window under the pointer             | testOverlayPick, testOverlayTargetsKnown, testOverlayTriggerHeld; live PASS 10-25                                        |
| Quick throw and throw by cursor direction              | Rectangle Pro | yes, by cursor direction                                        | testOverlayPick; live PASS 10-25                                                                                         |
| Custom snap targets and a configurable snap panel      | Rectangle Pro | yes, custom areas off the ultrawide and a snap panel on a pause | testSnapCustomAreas, testSnapPanelLayout, testSnapChoicesCustomDecode; snap panel live PASS 10-26, custom area drop owed |
| Custom sizes with repeat behavior                      | Rectangle Pro | yes                                                             | testCustomSize, testSizeShortcuts                                                                                        |
| Workspace arrangement by shortcut                      | Rectangle Pro | yes                                                             | testWorkspacesMatch, testWorkspacesFitAndCodable                                                                         |
| Workspace arrangement on display connect or disconnect | Rectangle Pro | yes                                                             | testWorkspacesSignature                                                                                                  |
| Stash at a screen edge with slide-out on hover         | Rectangle Pro | yes, left, right and bottom edges, no top edge                  | testStashFrames, testStashHover, testStashArms, testStashEdges, testStashedStaysPut; live PASS 10-26 on one display      |
| Pin one app to a side                                  | Rectangle Pro | yes                                                             | selftest "anchored window lands in its slot"                                                                             |
| Todo mode with more settings                           | Rectangle Pro | no (anchored apps cover the pinning, no separate mode)          | not applicable                                                                                                           |
| Menu customization, by shortcut or as a context menu   | Rectangle Pro | yes                                                             | testMenuVisible, testMenuPinned, live 10-24                                                                              |
| Import from Rectangle, export file or live settings    | Rectangle Pro | yes                                                             | testRectangleImportRoundTrip, testRectangleImportLive                                                                    |
| iCloud sync                                            | Rectangle Pro | planned (unit 20)                                               | unit 20 settings sync on iCloud                                                                                          |
| Windows-style arrow keys and left/right fill           | Rectangle Pro | yes                                                             | testArrowWalk, testFillLeftStops, testWindowsKeymap                                                                      |

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
| Restore                                                                                                                                                                                                                                                                        | Rectangle, Raycast         | yes, 10 deep      | testHistoryUndoRedo, testHistoryFromSave                                                          |
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
| Drag to an edge or corner with a footprint                                                                                                                                                                                                                                     | Rectangle, Magnet          | yes               | testSnapEdges, testPaletteFootprint                                                                 |
| Other hidden preferences (resizeOnDirectionalMove, centeredDirectionalMove, sizeOffset, curtainChangeSize, smallerShrinksMaximizedHeight, autoMaximize, attemptMatchOnNextPrevDisplay, moveFixedSizeToEdge, directAnimationNativeResizeApps, almost maximize width and height) | Rectangle                  | planned (unit 6)  | unit 6 behavior choices                                                                           |

## Moom

Moom costs $15.

| Feature                                                  | Who has it                  | Moorings                                                                           | Check                                          |
| -------------------------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------- |
| Pop-up palette on the green button with up to 61 actions | Moom                        | yes, as a menu at the pointer by shortcut or mouse button, not on the green button | live 10-24                                     |
| Saved layouts for an app's windows and recent windows    | Moom                        | yes                                                                                | testWorkspacesFitAndCodable                    |
| Snap zones                                               | Moom                        | yes                                                                                | testSnapEdges                                  |
| Drop zones from a saved layout                           | Moom                        | partial: custom areas drawn as shares, not made from a saved layout                | testSnapCustomAreas                            |
| Chains of actions, in sequence or looped                 | Moom                        | yes                                                                                | testChainStepStops, testChainStepLoops         |
| Hover move and resize with modifiers, no click           | Moom, Lasso                 | yes, keys picked in Settings > Behavior, resize from the nearest corner            | testHoverMode, testHoverFrame; live PASS 10-25 |
| Keyboard grid controller                                 | Moom                        | yes, arrows under the held key, Return applies                                     | testOverlayGrid; live PASS 10-25               |
| Folders in the menu                                      | Moom                        | no (fixed folders by family; actions are pinned or hidden instead)                 | not applicable                                 |
| Per-action grid sizes                                    | Moom                        | yes, grid takes the set size and grid:8x6 its own                                  | testOverlayGridSize                            |
| Use active window size                                   | Moom                        | planned (unit 5)                                                                   | unit 5 specified size                          |
| Display adjustment of layouts                            | Moom                        | yes                                                                                | testWorkspacesFitAndCodable                    |
| Dock, menu bar or invisible app modes                    | Moom                        | no (menu bar only by design)                                                       | not applicable                                 |
| Modifier drag to move or resize from anywhere            | Moom, BetterSnapTool, Lasso | yes, by hover: hold the keys and move, no click needed                             | testHoverMode, testHoverFrame; live PASS 10-25 |

## BetterSnapTool

It is sold on the Mac App Store. The price is not on the page.

| Feature                                         | Who has it             | Moorings               | Check                                          |
|-------------------------------------------------|------------------------|------------------------|------------------------------------------------|
| Corner and edge snapping                        | BetterSnapTool, Magnet | yes                    | testSnapEdges                                  |
| Custom snap areas anywhere                      | BetterSnapTool         | yes, off the ultrawide | testSnapCustomAreas; live check owed           |
| Custom shortcuts                                | BetterSnapTool         | yes                    | testSizeShortcuts                              |
| Green button lifts or fills instead of zoom     | BetterSnapTool         | yes                    | testLiftGreenButton                            |
| Customized clicks on the red and yellow buttons | BetterSnapTool         | yes                    | testButtonClicksAction                         |
| Move or resize while holding a key              | BetterSnapTool         | yes                    | testHoverMode, testHoverFrame; live PASS 10-25 |

## Loop

Loop is free and GPL-3 licensed.

| Feature                        | Who has it | Moorings                                                                                     | Check                                                                          |
| ------------------------------ | ---------- | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Radial menu on a trigger key   | Loop       | yes, 16 targets in two rings                                                                 | testOverlayPick, testOverlayTriggerHeld; live PASS 10-25                       |
| Preview outline while choosing | Loop       | yes, the snap footprint                                                                      | live PASS 10-25                                                                |
| Trigger-key chords             | Loop       | partial: arrows, Shift-arrows, Return and Escape under the trigger; no custom chords         | testOverlayTriggerHeld; live PASS 10-25                                        |
| Cycles                         | Loop       | yes                                                                                          | testCycle, testPressCycle                                                      |
| Stash                          | Loop       | yes, left, right and bottom edges                                                            | testStashFrames, testStashHover, testStashArms; live PASS 10-26 on one display |
| Theming                        | Loop       | partial: the footprint's color, opacity, border and fade; one palette for banners and panels | testFootprintStyleTints, testPaletteHarborContrast                             |

## Swish

Swish costs $16.

| Feature                                                                      | Who has it | Moorings                                    | Check                      |
| ---------------------------------------------------------------------------- | ---------- | ------------------------------------------- | -------------------------- |
| 30 trackpad gestures on title bars, Dock and menu bar                        | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Grid snapping by swipe, pinch to close or fullscreen, swipe down to minimize | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Spaces by gesture                                                            | Swish      | no (private API, owner call, unit 25 spike) | not applicable             |
| Divider drag that resizes several windows at once                            | Swish      | partial (two windows that share an edge)    | testSharedEdgeResize       |

## Stay

| Feature                              | Who has it | Moorings                                              | Check                                    |
| ------------------------------------ | ---------- | ----------------------------------------------------- | ---------------------------------------- |
| Window positions per set of displays | Stay       | yes                                                   | testWorkspacesSignature                  |
| Restore on display change            | Stay       | yes                                                   | testWorkspacesMatch                      |
| Automatic capture with no save step  | Stay       | partial: recall on any display change, after one save | testWorkspacesRecalling; live check owed |

## Amethyst

Amethyst is free and MIT licensed.

| Feature                                                                              | Who has it | Moorings                                                                                                                       | Check                                              |
| ------------------------------------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- |
| Layouts tall, tall-right, wide, two pane, 3column, widescreen-tall, column, row, BSP | Amethyst   | partial (tall, wide, columns, rows, BSP; retiled as windows come and go; not tall-right, two pane, 3column or widescreen-tall) | testTilingLayout; live PASS 10-26                  |
| Fullscreen and floating layouts                                                      | Amethyst   | partial (a dragged window floats until a layout is chosen again; no fullscreen layout)                                         | live PASS 10-26                                    |
| Custom JS layouts                                                                    | Amethyst   | no (out of scope, chains and profiles cover it)                                                                                | not applicable                                     |
| Focus and swap by direction, layout cycling                                          | Amethyst   | yes (focus and swap work with tiling off too; grow and shrink the main pane)                                                   | testTilingToward, testTilingOrder, testTilingNames |
| Per-space layouts                                                                    | Amethyst   | planned (unit 24)                                                                                                              | unit 24 spaces spike                               |
| YAML config                                                                          | Amethyst   | yes (one JSON file)                                                                                                            | testSettingsBackupRoundTrip                        |

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

| Feature                                 | Who has it           | Moorings                                                                            | Check                                                      |
|-----------------------------------------|----------------------|-------------------------------------------------------------------------------------|------------------------------------------------------------|
| Drag over a grid to pick a span         | Divvy, Mosaic, Lasso | yes, the grid action, by mouse or by arrow keys                                     | testOverlayGridSpan; live PASS 10-25                       |
| Quick positions without resizing        | Mosaic               | yes, edges, corners and center                                                      | testPosition                                               |
| Auto layout per app window              | Mosaic               | yes, app rules place the first window                                               | testWorkspacesAppRule; selftest rule case, live PASS 10-26 |
| Groups of layouts, switchable profiles  | Mosaic               | yes                                                                                 | testProfileApplyTouchesOnlySettings                        |
| Touch Bar                               | Mosaic               | no (Apple dropped the Touch Bar from current Macs)                                  | not applicable                                             |
| Window capture, iOS remote control      | Mosaic               | partial: window capture by app rules; iOS remote control later                      | testWorkspacesAppRule                                      |
| Saved layouts with per-layout shortcuts | Lasso                | yes                                                                                 | testWorkspacesFitAndCodable                                |
| iCloud sync                             | Lasso                | planned (unit 20)                                                                   | unit 20 settings sync on iCloud                            |
| Export and import                       | Lasso                | yes                                                                                 | testSettingsBackupRoundTrip                                |
| Rectangle keymap preset                 | Lasso                | yes                                                                                 | testRectangleDefaults                                      |
| Magnet keymap preset                    | Lasso                | yes (Magnet's site lists no shortcuts; the table is the Magnet set Rectangle ships) | testMagnet                                                 |

## Raycast window management

| Feature                                                | Who has it | Moorings                                                                       | Check                                   |
| ------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------ | --------------------------------------- |
| Rectangle action set                                   | Raycast    | yes (see the Rectangle table)                                                  | testAllNames                            |
| Move to Previous or Next Space, Move to Desktop 1 to 9 | Raycast    | planned (unit 24 spike)                                                        | unit 24 spaces spike                    |
| Rename Desktop                                         | Raycast    | no (macOS has no public call to name a Space)                                  | not applicable                          |
| Close a window                                         | Raycast    | yes (close-window)                                                             | testKnown                               |
| Open a window                                          | Raycast    | no (a new window is an app command; launching an app is covered by workspaces) | not applicable                          |
| Focus next or previous app window                      | Raycast    | yes (focus-next-window, focus-previous-window)                                 | testTileNeighbor, selftest focus case   |
| Exact size and position commands in points             | Raycast    | yes                                                                            | testPointsSpec, testSpecified           |
| Size and position as shares of the screen              | Raycast    | yes                                                                            | testCustomShare                         |
| Layouts of up to eight windows with launch arguments   | Raycast    | yes, no window limit, opens missing apps with a file or URL                    | testWorkspacesLaunches; live PASS 10-26 |
| Other windows behavior (minimize or close others)      | Raycast    | yes (minimize-others, close-others; anchored windows stay)                     | testKnown                               |
| Deeplinks                                              | Raycast    | yes (moorings:// links, Run Moorings Action in Shortcuts)                      | testKnown; Shortcuts live check owed    |

## Energy

Measured with `make bench` in mac/ (mac/scripts/bench.sh) on an M1 Max, macOS 26.6.1, on 2026-10-31 with a Moorings 1.16.2 candidate (build 98), Rectangle 2.0.4 and Loop 1.4.2, all three running side by side with Accessibility granted. Idle is two minutes at rest. Active sends 100 alternating left and right half actions to one window of the bench's own probe app through each app's own links, one app at a time, in three rounds that take turns between the apps. The table shows the median round. Paused is the CPU Moorings spends, paused, while Rectangle moves that window 100 times. Memory is each app's footprint at the end of the run.

| Measure                                | Moorings | Rectangle    | Loop         |
| -------------------------------------- | -------- | ------------ | ------------ |
| Memory                                 | 20 MB    | 22 MB        | 49 MB        |
| Idle CPU over 120 s                    | 0.00 s   | 0.00 s       | 0.01 s       |
| Active CPU per action                  | 3.2 ms   | 3.1 ms       | 23 ms        |
| Paused CPU per move another app makes  | 0.3 ms   | not measured | not measured |

The gate holds Moorings to at most 1.5 times Rectangle's memory and no more than Loop's, at most 0.03 s of CPU and no pass at rest, at most 2.0 times Rectangle's median CPU per action and no more than Loop's, and at most 1 ms per move while paused. `make bench` exits 1 on any miss, and no release is tagged until it passes on the build that ships. Moorings lands within a tenth of a millisecond of Rectangle per action, with the work that keeps the channel included.

Moorings does more than either app between shortcuts. It holds anchored apps in their slots and keeps free windows in the channel, so it watches every app's windows and keeps each action's frame inside the channel, where Rectangle sets one window and stops. At rest no pass runs until a window changes, and a paused Moorings runs no passes at all.

No layout timer fires at rest. A one-minute timer runs for the update check and sends a request only when a check is due. The stack badge, when on, reads the pointer four times a second. While something is stashed, mouse-moved and mouse-up events wake the stash, plus one check when the pointer has rested long enough to slide a window out.

mac/scripts/energy.sh stays as the long-sample tool, reading top's CPU and energy impact for each app over minutes.

## Compatibility

`moorings://selftest?apps=<bundle id>,<bundle id>` moves, resizes, snaps to the left half and restores the front free window of each named app, and logs PASS, FAIL or MIN per app and case with the app's version. An app that is not running is opened in the background and quit after. A window refused or rounded by its app shows the frame it kept in the FAIL line. MIN is a resize the app stopped above the asked size on the way down, at the asked origin, and held on a second try: the app's own minimum. A window that did not resize at all still fails. The cases are the ones every window manager depends on: moves and sizes through Accessibility land exactly.

Run on October 26, 2026, macOS 26.6.1, Moorings at commit 707f3a6 (Chrome and TextEdit again at a3da6b2), on a 5120 by 1440 display with apps anchored at both edges.

| App                       | Version       | Move | Resize | Snap left half | Restore |
| ------------------------- | ------------- | ---- | ------ | -------------- | ------- |
| Docker Desktop (Electron) | 4.13.0        | PASS | PASS   | PASS           | PASS    |
| VLC                       | 3.0.24        | PASS | PASS   | PASS           | PASS    |
| TextEdit                  | 1.20          | PASS | PASS   | PASS           | PASS    |
| Preview                   | 11.0          | PASS | PASS   | PASS           | PASS    |
| Google Chrome             | 155.0.8059.86 | PASS | MIN    | PASS           | PASS    |

Chrome's resize case asks for 900 by 600 and Chrome keeps 900 by 652. A direct Accessibility resize from System Events gets the same 652, so that height is Chrome's own minimum for the window, not a frame Moorings lost, and the selftest reads it as MIN. Slack, Microsoft Word and a JetBrains IDE are not in the table yet. Docker Desktop stands in for Electron apps until Slack is run.

## What only Moorings has

None of the products above hold apps at the edges of an ultrawide with a channel between them.

| Feature                                     | Who has it | Moorings | Check                                                                 |
| ------------------------------------------- | ---------- | -------- | --------------------------------------------------------------------- |
| Anchored apps in edge slots on an ultrawide | Moorings   | yes      | selftest "anchored window lands in its slot"                          |
| Channel with push back for free windows     | Moorings   | yes      | testPushAndShrink                                                     |
| A slot holds all of an app's windows        | Moorings   | yes      | testSlotStacksHoldsAll, testLiftSecondWindowFullscreenStacks          |
| Halves and thirds inside a slot             | Moorings   | yes      | testSlotPartHeld, testSlotPartPruned                                  |
| Cycle the windows of a slot                 | Moorings   | yes      | testNextSlotWindowWraps                                               |
| Anchored app's extra windows off the strips | Moorings   | yes      | testAnchoredAppOtherWindows, testPinHoldsMainWindow                   |
| Lift an anchored window over the channel    | Moorings   | yes      | testLiftLiftsAndLowers                                                |
| Cast off a window over the strips           | Moorings   | yes      | testCastOffStaysPut                                                   |
| Drag release of an anchored window          | Moorings   | yes      | selftest "dragging the anchored window by its title bar releases it"  |
