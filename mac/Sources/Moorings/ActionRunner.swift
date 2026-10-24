import AppKit
import os

import MooringsCore

// Family groups window actions for the Window folder in the menu.
struct Family {
    // title is the family's folder name.
    let title: String
    // hint is the hover hint of every entry, nil when each entry has its own.
    let hint: String?
    // names lists the actions in menu order, empty when the family has groups.
    let names: [String]
    // groups lists sub-folders by title, empty when the family lists names.
    let groups: [(title: String, names: [String])]
}

// ActionRunner applies window actions to the focused window: halves, thirds, sizes, displays and
// the rest, stepping through a cycle on repeat presses.
@MainActor
final class ActionRunner {
    // families lists the action families in menu order.
    static let families: [Family] = [
        Family(title: "Halves", hint: "Snap the front window to this half.",
               names: ["left-half", "right-half", "center-half", "top-half", "bottom-half"], groups: []),
        Family(title: "Quarters", hint: "Snap the front window to this quarter.",
               names: ["top-left", "top-right", "bottom-left", "bottom-right"], groups: []),
        Family(title: "Thirds", hint: "Snap the front window to this part, in thirds.",
               names: ["first-third", "center-third", "last-third", "first-two-thirds", "center-two-thirds",
                       "last-two-thirds"], groups: []),
        Family(title: "Fourths", hint: "Snap the front window to this part, in fourths.",
               names: ["first-fourth", "second-fourth", "third-fourth", "last-fourth", "first-three-fourths",
                       "center-three-fourths", "last-three-fourths"], groups: []),
        Family(title: "Grids", hint: "Snap the front window to this grid cell.", names: [],
               groups: [("Sixths", Geometry.grids["sixths"] ?? []), ("Eighths", Geometry.grids["eighths"] ?? []),
                        ("Ninths", Geometry.grids["ninths"] ?? []),
                        ("Twelfths", Geometry.grids["twelfths"] ?? []),
                        ("Sixteenths", Geometry.grids["sixteenths"] ?? []),
                        ("Vertical thirds", Geometry.grids["verticalThirds"] ?? []),
                        ("Vertical sixths", Geometry.grids["verticalSixths"] ?? []),
                        ("Vertical eighths", Geometry.grids["verticalEighths"] ?? []),
                        ("Corner thirds", Geometry.grids["cornerThirds"] ?? [])]),
        Family(title: "Size and move", hint: nil,
               names: ["maximize", "almost-maximize", "maximize-height", "center", "center-prominently", "larger",
                       "smaller", "move-left", "move-right", "move-up", "move-down", "specified", "restore"], groups: []),
        Family(title: "One axis", hint: nil,
               names: ["larger-width", "smaller-width", "larger-height", "smaller-height", "double-width-left",
                       "double-width-right", "double-height-up", "double-height-down", "halve-width-left",
                       "halve-width-right", "halve-height-up", "halve-height-down"], groups: []),
        Family(title: "Displays", hint: "Send the front window to this display, keeping its place in the layout.",
               names: ["previous-display", "next-display"] + Actions.displayNames, groups: []),
    ]

    // hints holds the hover hints of the actions whose family has no shared hint.
    static let hints: [String: String] = [
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
        "specified": "Size the front window to the specified size, 1680 by 1050 points unless changed, centered, "
            + "shrunk to fit.",
        "restore": "Put the front window back where it was before moorings first moved it.",
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
    ]

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why an action did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "actions")
    // last records the last action applied to each window, so a repeat press steps its cycle.
    private var last: [WindowID: LastPress] = [:]

    // init builds a runner for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // anchors is the layout the actions read.
    private var anchors: Anchors { app.anchors }

    // run applies action name to the focused window and reports whether anything moved. Nothing runs
    // while the anchor is weighed. On a pin, Maximize lifts or lowers it and Restore re-moors it.
    @discardableResult
    func run(_ name: String) -> Bool {
        guard !anchors.choices.paused, app.windows.trusted else { return false }
        if Tile.handles(name) {
            return app.organizer.run(name)
        }
        if name.hasPrefix(Keymaps.workspacePrefix) {
            return app.organizer.recall(String(name.dropFirst(Keymaps.workspacePrefix.count)))
        }
        let screens = Screens.current()
        guard let w = app.windows.scan(screens).focused else {
            logger.notice("\(name, privacy: .public): no focused window")
            return false
        }
        guard apply(name, to: w, screens: screens) else { return false }
        if anchors.choices.behavior.moveCursor, let f = app.windows.frame(w.id) {
            CGWarpMouseCursorPosition(CGPoint(x: f.x + f.w / 2, y: f.y + f.h / 2))
        }
        return true
    }

    // apply applies action name to window w on the screen at index, its own screen when nil, and
    // reports whether it moved.
    @discardableResult
    func apply(_ name: String, to w: WindowInfo, screens: Screens, index: Int? = nil) -> Bool {
        if anchors.pinned(w) {
            switch name {
            case "maximize":
                anchors.toggleLift(w)
                if anchors.isLifted(w.id) {
                    app.windows.raise(w.id)
                }
                app.wake()
                app.moor()
                return true
            case "restore":
                anchors.remoor(w.id)
                app.wake()
                app.moor()
                return true
            default:
                logger.notice("the window is pinned: window actions leave pins alone")
                return false
            }
        }
        if w.isFullScreen {
            return false
        }
        if name == "restore" {
            last[w.id] = nil
            guard let f = anchors.restore(w.id) else { return false }
            app.windows.move(w.id, to: f)
            app.wake()
            return true
        }
        let (frame, press, result) = frame(name, for: w, screens: screens, index: index)
        guard let frame else { return false }
        anchors.save(w)
        app.windows.move(w.id, to: frame, enhancedUI: anchors.choices.behavior.enhancedUI)
        last[w.id] = LastPress(name: result, press: press, frame: app.windows.frame(w.id) ?? frame)
        app.wake()
        return true
    }

    // frame returns the frame action name gives w on the screen at index, its own screen when nil,
    // the press count, and the action the result counts as, without moving it.
    func frame(
        _ name: String, for w: WindowInfo, screens: Screens, index: Int? = nil
    ) -> (Frame?, press: Int, name: String) {
        let areas = screens.usable.indices.map { i in
            i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
        }
        let right = Self.stageOnRight()
        let notched = Set(NSScreen.screens.indices.filter { NSScreen.screens[$0].safeAreaInsets.top > 0 })
        let target = ActionTarget(screens: screens.full, areas: areas, index: index ?? screens.index(w.frame) ?? 0,
                                  notched: notched, staged: Self.staged(screens.full, right: right),
                                  stageOnRight: right)
        return Actions.frame(name, cur: w.frame, target: target, gap: anchors.choices.gapPx,
                             sizes: Bindings(anchors.choices).specs, last: last[w.id],
                             behavior: anchors.choices.behavior)
    }

    // windowManager reads a Stage Manager setting from the WindowManager defaults.
    private static func windowManager(_ key: String) -> Bool? {
        UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: key) as? Bool
    }

    // stageOnRight reports whether the Stage Manager strip sits on the right: with the Dock on the
    // left, or with the Dock at the bottom in a right-to-left language.
    private static func stageOnRight() -> Bool {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": true
        case "right": false
        default: Locale.current.language.characterDirection == .rightToLeft
        }
    }

    // staged lists the screens showing the Stage Manager strip: Stage Manager is on, the strip is not
    // set to hide, and at least two WindowManager windows sit at the screen's strip edge. One alone
    // can be the window being dragged.
    private static func staged(_ full: [Frame], right: Bool) -> Set<Int> {
        guard windowManager("GloballyEnabled") == true, windowManager("AutoHide") != true else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [Int: Int] = [:]
        for entry in list where entry[kCGWindowOwnerName as String] as? String == "WindowManager" {
            guard let b = entry[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { continue }
            let rows = full.indices.filter { full[$0].y <= y && y + h <= full[$0].y + full[$0].h }
            let edge = { (i: Int) in right ? abs(full[i].x + full[i].w - (x + w)) : abs(x - full[i].x) }
            if let i = rows.min(by: { edge($0) < edge($1) }) {
                counts[i, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }

    // runnable reports whether name is an action or a custom size in the choices.
    func runnable(_ name: String) -> Bool {
        Keymaps.known(name) || Bindings(anchors.choices).specs[name] != nil
    }
}
