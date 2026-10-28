import MooringsCore

// Family groups window actions for the Window folder in the menu.
public struct Family: Sendable {
    // title is the family's folder name.
    public let title: String
    // hint is the hover hint of every entry, nil when each entry has its own.
    public let hint: String?
    // names lists the actions in menu order, empty when the family has groups.
    public let names: [String]
    // groups lists sub-folders by title, empty when the family lists names.
    public let groups: [(title: String, names: [String])]
}

// ActionRunner's families, hints and placesFrame describe the actions for the menus on every
// platform.
extension ActionRunner {
    // families lists the action families in menu order.
    public static let families: [Family] = [
        Family(
            title: "Halves", hint: "Snap the front window to this half.",
            names: ["left-half", "right-half", "center-half", "top-half", "bottom-half"], groups: []),
        Family(
            title: "Quarters", hint: "Snap the front window to this quarter.",
            names: ["top-left", "top-right", "bottom-left", "bottom-right"], groups: []),
        Family(
            title: "Thirds", hint: "Snap the front window to this part, in thirds.",
            names: [
                "first-third", "center-third", "last-third", "first-two-thirds", "center-two-thirds",
                "last-two-thirds",
            ], groups: []),
        Family(
            title: "Fourths", hint: "Snap the front window to this part, in fourths.",
            names: [
                "first-fourth", "second-fourth", "third-fourth", "last-fourth", "first-three-fourths",
                "center-three-fourths", "last-three-fourths",
            ], groups: []),
        Family(
            title: "Grids", hint: "Snap the front window to this grid cell.", names: [],
            groups: [
                ("Sixths", Geometry.grids["sixths"] ?? []), ("Eighths", Geometry.grids["eighths"] ?? []),
                ("Ninths", Geometry.grids["ninths"] ?? []),
                ("Twelfths", Geometry.grids["twelfths"] ?? []),
                ("Sixteenths", Geometry.grids["sixteenths"] ?? []),
                ("Vertical thirds", Geometry.grids["verticalThirds"] ?? []),
                ("Vertical sixths", Geometry.grids["verticalSixths"] ?? []),
                ("Vertical eighths", Geometry.grids["verticalEighths"] ?? []),
                ("Corner thirds", Geometry.grids["cornerThirds"] ?? []),
            ]),
        Family(
            title: "Size and move", hint: nil,
            names: [
                "maximize", "almost-maximize", "maximize-height", "center", "center-prominently", "larger",
                "smaller", "move-left", "move-right", "move-up", "move-down", "move-top-left", "move-top-right",
                "move-bottom-left", "move-bottom-right", "specified", "restore", "undo-move", "redo-move",
                Overlay.gridName,
            ], groups: []),
        Family(
            title: "One axis", hint: nil,
            names: [
                "larger-width", "smaller-width", "larger-height", "smaller-height", "double-width-left",
                "double-width-right", "double-height-up", "double-height-down", "halve-width-left",
                "halve-width-right", "halve-height-up", "halve-height-down",
            ], groups: []),
        Family(title: "Arrow mode", hint: nil, names: Actions.arrowNames + Actions.fillNames, groups: []),
        Family(title: "Front app", hint: nil, names: Keymaps.windowNames, groups: []),
        Family(title: "Stash", hint: nil, names: Keymaps.stashNames, groups: []),
        Family(
            title: "Displays", hint: "Send the front window to this display, keeping its place in the layout.",
            names: ["previous-display", "next-display"] + Actions.displayNames, groups: []),
    ]

    // hints holds the hover hints of the actions whose family has no shared hint.
    public static let hints: [String: String] = [
        "maximize": "Fill the whole area with the front window.",
        "almost-maximize": "Fill most of the area with the front window, centered.",
        "maximize-height": "Stretch the front window to the full height, keeping its width.",
        "center": "Center the front window, keeping its size.",
        "center-prominently": "Center the front window a little above the middle.",
        "larger": "Grow the front window. Edges touching the area stay put.",
        "smaller": "Shrink the front window. Edges touching the area stay put.",
        "move-left": "Move the front window to the left edge, keeping its size.",
        "move-right": "Move the front window to the right edge, keeping its size.",
        "move-up": "Move the front window to the top edge, keeping its size.",
        "move-down": "Move the front window to the bottom edge, keeping its size.",
        "move-top-left": "Move the front window to the top left corner, keeping its size.",
        "move-top-right": "Move the front window to the top right corner, keeping its size.",
        "move-bottom-left": "Move the front window to the bottom left corner, keeping its size.",
        "move-bottom-right": "Move the front window to the bottom right corner, keeping its size.",
        Overlay.gridName: "Show a grid over the front window's area and drag across cells to fill them. Arrow "
            + "keys and Return work too, and Escape puts the grid away.",
        "specified": "Size the front window to the specified size, 1680 by 1050 points unless changed, centered, "
            + "shrunk to fit.",
        "restore": "Put the front window back where it was before moorings first moved it.",
        "undo-move": "Step the front window back to where it was before its last move by moorings, up to ten moves.",
        "redo-move": "Step the front window forward again after an undo.",
        "larger-width": "Widen the front window, keeping its height.",
        "smaller-width": "Narrow the front window, keeping its height.",
        "larger-height": "Make the front window taller, keeping its width.",
        "smaller-height": "Make the front window shorter, keeping its width.",
        "double-width-left": "Double the front window's width toward the left edge.",
        "double-width-right": "Double the front window's width toward the right edge.",
        "double-height-up": "Double the front window's height toward the top.",
        "double-height-down": "Double the front window's height toward the bottom.",
        "halve-width-left": "Halve the front window's width, keeping its left half.",
        "halve-width-right": "Halve the front window's width, keeping its right half.",
        "halve-height-up": "Halve the front window's height, keeping its top half.",
        "halve-height-down": "Halve the front window's height, keeping its bottom half.",
        "arrow-left": "Left half, then the next quarter or display to the left, from where the front window is.",
        "arrow-right": "Right half, then the next quarter or display to the right, from where the front window is.",
        "arrow-up": "Maximize a free window, or move a half or quarter up a step.",
        "arrow-down": "Restore a maximized window, move a half or quarter down a step, or minimize a free one.",
        "fill-left": "Grow the front window left to the next window or the edge, keeping its right edge.",
        "fill-right": "Grow the front window right to the next window or the edge, keeping its left edge.",
        "focus-next-window": "Bring the front app's next window forward, in the order they were opened.",
        "focus-previous-window": "Bring the front app's previous window forward, in the order they were opened.",
        "minimize-window": "Send the front window to the Dock.",
        "close-window": "Close the front window, as its close button does.",
        "minimize-others": "Send every other window of the front app to the Dock. Anchored windows stay.",
        "close-others": "Close every other window of the front app. Anchored windows stay.",
        "stash": "Park the front window at the nearest free screen edge, or bring it back if it is parked. "
            + "Rest the pointer on its edge to slide it out.",
        "unstash-all": "Bring every parked window back where it was.",
        Tiling.cycleName: "Step to the next tiling layout.",
        "grow-main": "Give the main window more of the area in the tall and wide layouts.",
        "shrink-main": "Give the main window less of the area in the tall and wide layouts.",
    ]

    // placesFrame reports whether action name puts a window at a frame, so a snap area can take it.
    // Front app actions, arrow mode, stash and the grid act on something else first.
    public static func placesFrame(_ name: String) -> Bool {
        !Keymaps.windowNames.contains(name) && !Actions.arrowNames.contains(name) && !Keymaps.stashNames.contains(name)
            && Overlay.gridSize(name, OverlayChoices()) == nil
    }
}
