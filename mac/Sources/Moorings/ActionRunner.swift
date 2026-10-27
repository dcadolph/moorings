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
                       "smaller", "move-left", "move-right", "move-up", "move-down", "move-top-left", "move-top-right",
                       "move-bottom-left", "move-bottom-right", "specified", "restore", "undo-move", "redo-move",
                       Overlay.gridName], groups: []),
        Family(title: "One axis", hint: nil,
               names: ["larger-width", "smaller-width", "larger-height", "smaller-height", "double-width-left",
                       "double-width-right", "double-height-up", "double-height-down", "halve-width-left",
                       "halve-width-right", "halve-height-up", "halve-height-down"], groups: []),
        Family(title: "Arrow mode", hint: nil, names: Actions.arrowNames + Actions.fillNames, groups: []),
        Family(title: "Front app", hint: nil, names: Keymaps.windowNames, groups: []),
        Family(title: "Stash", hint: nil, names: Keymaps.stashNames, groups: []),
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
    static func placesFrame(_ name: String) -> Bool {
        !Keymaps.windowNames.contains(name) && !Actions.arrowNames.contains(name) && !Keymaps.stashNames.contains(name)
            && Overlay.gridSize(name, OverlayChoices()) == nil
    }

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why an action did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "actions")
    // last records the last action applied to each window, so a repeat press steps its cycle.
    private var last: [WindowID: LastPress] = [:]
    // chainPress records the last chain run, the window it ran on and its zero-based press count.
    private var chainPress: (name: String, window: WindowID?, press: Int)?

    // init builds a runner for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // anchors is the layout the actions read.
    private var anchors: Anchors { app.anchors }

    // run applies action name to the window with id window, raised first, or to the focused window
    // when nil, and reports whether anything moved. Nothing runs while the anchor is weighed. On a
    // pin, Maximize lifts or lowers it and Restore re-moors it. A chain runs its next step, and the
    // menu action opens the menu under the pointer.
    @discardableResult
    func run(_ name: String, window: WindowID? = nil) -> Bool {
        if name == Keymaps.menuName {
            DispatchQueue.main.async { [app] in app.popMenu() }
            return true
        }
        if name == Keymaps.stripsName {
            DispatchQueue.main.async { [app] in app.strips.show() }
            return true
        }
        guard !anchors.choices.paused, app.windows.trusted else { return false }
        if let window {
            app.windows.raise(window)
        }
        if name.hasPrefix(Chain.prefix) {
            return runChain(String(name.dropFirst(Chain.prefix.count)), window: window)
        }
        chainPress = nil
        return perform(name, window: window)
    }

    // runChain runs the next step of the chain titled title on window, or the focused window when nil.
    // A press counts as the next one only when the same chain last ran on the same window with nothing
    // run in between.
    private func runChain(_ title: String, window: WindowID?) -> Bool {
        guard let chain = anchors.choices.chains.first(where: { $0.name == title }) else {
            logger.notice("chain \(title, privacy: .public): no such chain")
            return false
        }
        let window = window ?? app.windows.scan(Screens.current()).focused?.id
        let press = chainPress.map { $0.name == title && $0.window == window ? $0.press + 1 : 0 } ?? 0
        chainPress = (title, window, press)
        guard let step = chain.step(press: press) else {
            logger.notice("chain \(title, privacy: .public): no steps")
            return false
        }
        return perform(step, window: window)
    }

    // perform applies action name, which is not a chain, to the window with id window, or to the
    // focused window when nil. Actions on the front app or several windows act on the front app.
    // A placement reads only its window, and scans the front app and the apps whose windows changed
    // since the last scan when that window cannot be read alone or belongs to an anchored app, whose
    // pin depends on every window of the app.
    private func perform(_ name: String, window: WindowID? = nil) -> Bool {
        if let size = Overlay.gridSize(name, anchors.choices.overlay) {
            return app.gridPicker.show(cols: size.cols, rows: size.rows, window: window)
        }
        if Keymaps.windowNames.contains(name) {
            return frontApp(name)
        }
        if Keymaps.stashNames.contains(name) {
            return app.stasher.run(name)
        }
        if Tile.handles(name) {
            return app.organizer.run(name)
        }
        if Tiling.handles(name) {
            return app.tiler.run(name)
        }
        if name.hasPrefix(Keymaps.workspacePrefix) {
            return app.organizer.recall(String(name.dropFirst(Keymaps.workspacePrefix.count)))
        }
        if name.hasPrefix(Profile.prefix) {
            let title = String(name.dropFirst(Profile.prefix.count))
            guard anchors.choices.profiles.contains(where: { $0.name == title }) else { return false }
            DispatchQueue.main.async { [app] in app.organizer.applyProfile(title) }
            return true
        }
        let screens = Screens.current()
        guard let w = subject(window, screens: screens) else {
            logger.notice("\(name, privacy: .public): no focused window")
            return false
        }
        guard apply(name, to: w, screens: screens) else { return false }
        if anchors.choices.behavior.moveCursor, let f = app.windows.frame(w.id) {
            CGWarpMouseCursorPosition(CGPoint(x: f.x + f.w / 2, y: f.y + f.h / 2))
        }
        return true
    }

    // subject returns the window with id window, or the focused window when nil, read alone when it
    // can be and scanned otherwise.
    private func subject(_ window: WindowID?, screens: Screens) -> WindowInfo? {
        let alone = if let window { app.windows.window(window, screens: screens) } else { app.windows.focused(screens) }
        if let alone, !anchors.pins().contains(where: { $0.bundle == alone.bundle }) {
            return alone
        }
        let scan = app.windows.scan(screens) { listed, previous, slow, front in
            .apps(PassPlan.changed(listed: listed, previous: previous, slow: slow).union(front.map { [$0] } ?? []))
        }
        return window.flatMap { id in scan.windows.first { $0.id == id } } ?? scan.focused
    }

    // frontApp runs a window action on the focused app's windows: bring its next or previous window
    // forward, minimize or close the focused one, or minimize or close every other one. None moves a
    // frame. Anchored windows are left alone, except that close-window closes one as its close button
    // would.
    private func frontApp(_ name: String) -> Bool {
        let scan = app.windows.scan(Screens.current())
        guard let w = scan.focused else {
            logger.notice("\(name, privacy: .public): no focused window")
            return false
        }
        let mine = scan.windows.filter { $0.bundle == w.bundle && !$0.isFilePanel }
        switch name {
        case "focus-next-window", "focus-previous-window":
            guard let next = Tile.neighbor(mine.map(\.id), of: w.id, forward: name == "focus-next-window") else {
                logger.notice("\(name, privacy: .public): the front app has no other window")
                return false
            }
            app.windows.raise(next)
            return true
        case "close-window":
            app.windows.close(w.id)
            return true
        case "minimize-window":
            guard !anchors.pinned(w) else {
                logger.notice("the window is pinned: window actions leave pins alone")
                return false
            }
            app.windows.minimize(w.id)
            return true
        default:
            let others = mine.filter { $0.id != w.id && !anchors.pinned($0) }
            for o in others {
                if name == "minimize-others" {
                    app.windows.minimize(o.id)
                } else {
                    app.windows.close(o.id)
                }
            }
            return !others.isEmpty
        }
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
            anchors.history.record(w.id, from: w.frame)
            app.windows.move(w.id, to: f)
            app.wake()
            return true
        }
        if name == "undo-move" || name == "redo-move" {
            last[w.id] = nil
            let f = name == "undo-move" ? anchors.history.undo(w.id, current: w.frame)
                : anchors.history.redo(w.id, current: w.frame)
            guard let f else {
                logger.notice("\(name, privacy: .public): nothing to step to for this window")
                return false
            }
            app.windows.move(w.id, to: f)
            app.wake()
            return true
        }
        if Actions.arrowNames.contains(name) {
            switch Actions.arrow(name, cur: w.frame, target: target(for: w, screens: screens, index: index),
                                 gap: anchors.choices.gapPx, behavior: anchors.choices.behavior) {
            case let .frame(f, landed):
                return place(w, at: f, press: 1, name: landed)
            case .restore:
                return apply("restore", to: w, screens: screens)
            case .minimize:
                app.windows.minimize(w.id)
                return true
            case .stay:
                return false
            }
        }
        if Behavior.restoresMaximize(name, cur: w.frame, last: last[w.id], anchors.choices.behavior) {
            return apply("restore", to: w, screens: screens)
        }
        let (frame, press, result) = frame(name, for: w, screens: screens, index: index)
        guard let frame else { return false }
        return place(w, at: frame, press: press, name: result)
    }

    // applyFrame raises the window with id and moves it to frame as a placement restore can undo, and
    // reports whether it moved. Pinned and fullscreen windows stay put.
    @discardableResult
    func applyFrame(_ frame: Frame, to id: WindowID) -> Bool {
        guard !anchors.choices.paused, app.windows.trusted else { return false }
        guard let w = app.windows.scan(Screens.current()).windows.first(where: { $0.id == id }),
              !anchors.pinned(w), !w.isFullScreen
        else { return false }
        app.windows.raise(id)
        chainPress = nil
        return place(w, at: frame, press: 1, name: "grid")
    }

    // area returns the area actions on w use on its own screen.
    func area(for w: WindowInfo, screens: Screens) -> Frame {
        let t = target(for: w, screens: screens)
        return Actions.area(t, t.index, anchors.choices.behavior)
    }

    // place moves w to frame and records it as press of action name, so a repeat press steps on.
    private func place(_ w: WindowInfo, at frame: Frame, press: Int, name: String) -> Bool {
        anchors.save(w)
        let b = anchors.choices.behavior
        if b.animate {
            app.windows.slide(w.id, from: w.frame, to: frame, enhancedUI: b.enhancedUI)
        } else {
            app.windows.move(w.id, to: frame, enhancedUI: b.enhancedUI, from: w.frame)
        }
        let landed = app.windows.frame(w.id) ?? frame
        last[w.id] = LastPress(name: name, press: press, frame: landed)
        app.landed(w.id, at: landed)
        if app.windows.pid(w.id) != nil {
            app.echo(w.id, at: landed)
        } else {
            app.wake()
        }
        return true
    }

    // target returns the screens an action on w may use, with w on the screen at index, its own
    // screen when nil.
    private func target(for w: WindowInfo, screens: Screens, index: Int? = nil) -> ActionTarget {
        let areas = screens.usable.indices.map { i in
            i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
        }
        let right = Self.stageOnRight()
        let notched = Set(NSScreen.screens.indices.filter { NSScreen.screens[$0].safeAreaInsets.top > 0 })
        return ActionTarget(screens: screens.full, areas: areas, index: index ?? screens.index(w.frame) ?? 0,
                            notched: notched, staged: Self.staged(screens.full, right: right), stageOnRight: right)
    }

    // frame returns the frame action name gives w on the screen at index, its own screen when nil,
    // the press count, and the action the result counts as, without moving it. A fill stops at the
    // other windows on screen.
    func frame(
        _ name: String, for w: WindowInfo, screens: Screens, index: Int? = nil
    ) -> (Frame?, press: Int, name: String) {
        let target = target(for: w, screens: screens, index: index)
        if Actions.fillNames.contains(name) {
            let area = Actions.area(target, target.index, anchors.choices.behavior)
            let others = app.windows.scan(screens).windows.filter { $0.id != w.id }.map(\.frame)
            let f = Geometry.fill(w.frame, name == "fill-left" ? .left : .right, area: area, others: others,
                                  gap: anchors.choices.gapPx)
            return (f == w.frame ? nil : f, 1, name)
        }
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

    // placed returns the frame the last action gave the window with id, nil when none has.
    func placed(_ id: WindowID) -> Frame? {
        last[id]?.frame
    }

    // unsnap gives the dragged window w, now at current, back the size it had before moorings first
    // moved it, with the cursor grab points from its left edge kept over it, and forgets the snap.
    func unsnap(_ w: WindowInfo, at current: Frame, grab: Double) {
        let saved = anchors.savedFrame(w.id).map { (w: $0.w, h: $0.h) }
        guard let size = Behavior.unsnapSize(anchors.choices.behavior, wasSnapped: true, saved: saved, current: current)
        else { return }
        let f = Behavior.unsnapFrame(current, size: size, grab: grab)
        if f.x == current.x {
            app.windows.resize(w.id, w: f.w, h: f.h)
        } else {
            app.windows.move(w.id, to: f)
        }
        _ = anchors.restore(w.id)
        last[w.id] = nil
    }

    // titleBarClick maximizes or restores the window whose title bar was double-clicked at p. It needs
    // the choice on and macOS set to do nothing on a title bar double-click, as Rectangle does, so
    // the two never both act. The window is read after the event, never inside the tap.
    func titleBarClick(_ p: CGPoint) {
        let b = anchors.choices.behavior
        guard b.doubleClickTitleBar, !anchors.choices.paused, app.windows.trusted else { return }
        guard UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") == "None" else {
            logger.notice("title bar double-click: macOS handles it; set Double-click a window's title bar to Do Nothing")
            return
        }
        DispatchQueue.main.async { [self] in
            guard let hit = Windows.hit(p),
                  Behavior.onTitleBar(Point(x: p.x, y: p.y), window: hit.frame, button: hit.button, role: hit.role)
            else { return }
            let screens = Screens.current()
            guard let w = app.windows.scan(screens).windows.first(where: { $0.id == hit.id }),
                  !b.doubleClickIgnoredApps.contains(w.bundle)
            else { return }
            apply(Behavior.titleBarAction(last: last[w.id], frame: w.frame), to: w, screens: screens)
        }
    }

    // runnable reports whether name is an action, or a custom size or chain in the choices.
    func runnable(_ name: String) -> Bool {
        if name.hasPrefix(Chain.prefix) {
            return anchors.choices.chains.contains { $0.actionName == name }
        }
        return Keymaps.known(name) || Bindings(anchors.choices).specs[name] != nil
    }
}
