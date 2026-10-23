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
                        ("Corner thirds", Geometry.grids["cornerThirds"] ?? [])]),
        Family(title: "Size and move", hint: nil,
               names: ["maximize", "almost-maximize", "maximize-height", "center", "center-prominently", "larger",
                       "smaller", "move-left", "move-right", "move-up", "move-down", "restore"], groups: []),
        Family(title: "Displays", hint: "Send the front window to this display, keeping its place in the layout.",
               names: ["previous-display", "next-display"], groups: []),
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
        "restore": "Put the front window back where it was before moorings first moved it.",
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
        let screens = Screens.current()
        guard let w = app.windows.scan(screens).focused else {
            logger.notice("\(name, privacy: .public): no focused window")
            return false
        }
        return apply(name, to: w, screens: screens)
    }

    // apply applies action name to window w and reports whether it moved.
    @discardableResult
    func apply(_ name: String, to w: WindowInfo, screens: Screens) -> Bool {
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
        let areas = screens.usable.indices.map { i in
            i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
        }
        let target = ActionTarget(screens: screens.full, areas: areas, index: screens.index(w.frame) ?? 0)
        let (frame, press) = Actions.frame(name, cur: w.frame, target: target, gap: anchors.choices.gapPx,
                                           sizes: Bindings(anchors.choices).specs, last: last[w.id])
        guard let frame else { return false }
        anchors.save(w)
        app.windows.move(w.id, to: frame)
        last[w.id] = LastPress(name: name, press: press, frame: app.windows.frame(w.id) ?? frame)
        app.wake()
        return true
    }

    // runnable reports whether name is an action or a custom size in the choices.
    func runnable(_ name: String) -> Bool {
        Keymaps.known(name) || Bindings(anchors.choices).specs[name] != nil
    }
}
