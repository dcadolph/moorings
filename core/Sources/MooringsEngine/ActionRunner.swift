import MooringsCore

// ExtraActions runs the actions the engine does not own yet on one platform: the grid, stash,
// organize, tiling, workspaces, profiles and the menus.
public struct ExtraActions {
    // handles reports whether the platform runs action name.
    public var handles: (String) -> Bool
    // run runs action name on a window, the focused one when nil, and reports whether it acted.
    public var run: (String, WindowID?) -> Bool

    // none is a platform that runs none of them.
    public static var none: ExtraActions { ExtraActions(handles: { _ in false }, run: { _, _ in false }) }

    // init builds the hook from its two parts.
    public init(handles: @escaping (String) -> Bool, run: @escaping (String, WindowID?) -> Bool) {
        self.handles = handles
        self.run = run
    }
}

// ActionRunner applies window actions to the focused window: halves, thirds, sizes, displays and
// the rest, stepping through a cycle on repeat presses. It runs chains one step per press and the
// front app's window actions, and hands the actions it does not own to the platform's extra hook.
public final class ActionRunner {
    // extra runs the actions the engine routes to the platform.
    public var extra = ExtraActions.none
    // read returns the window with an id, or the focused window when nil, read alone when the platform
    // can do that cheaply, nil to fall back to a scan.
    public var read: (WindowID?, Screens) -> WindowInfo? = { _, _ in nil }
    // landed is told each window an action moved and the frame it read back at.
    public var landed: (WindowID, Frame) -> Void = { _, _ in }
    // wake marks windows as changing, so passes run until they settle.
    public var wake: () -> Void = {}
    // moor runs a pass now.
    public var moor: () -> Void = {}
    // log writes why an action did nothing.
    public var log: (String) -> Void = { _ in }

    // platform reads and moves the windows.
    private let platform: Platform
    // anchors is the layout the actions read.
    private let anchors: Anchors
    // last records the last action applied to each window, so a repeat press steps its cycle.
    private var last: [WindowID: LastPress] = [:]
    // chainPress records the last chain run, the window it ran on and its zero-based press count.
    private var chainPress: (name: String, window: WindowID?, press: Int)?

    // init builds a runner on platform and anchors.
    public init(platform: Platform, anchors: Anchors) {
        self.platform = platform
        self.anchors = anchors
    }

    // routed reports whether the engine hands action name to the platform's extra hook.
    public func routed(_ name: String) -> Bool {
        name == Keymaps.menuName || name == Keymaps.stripsName || Overlay.gridSize(name, anchors.choices.overlay) != nil
            || Keymaps.stashNames.contains(name) || Tile.handles(name) || Tiling.handles(name)
            || name.hasPrefix(Keymaps.workspacePrefix) || name.hasPrefix(Profile.prefix)
    }

    // runnable reports whether name is an action, or a custom size or chain in the choices.
    public func runnable(_ name: String) -> Bool {
        if name.hasPrefix(Chain.prefix) {
            return anchors.choices.chains.contains { $0.actionName == name }
        }
        return Keymaps.known(name) || Bindings(anchors.choices).specs[name] != nil
    }

    // supports reports whether this platform runs action name: runnable, and either the engine's own
    // or one the extra hook handles.
    public func supports(_ name: String) -> Bool {
        runnable(name) && (!routed(name) || extra.handles(name))
    }

    // prune drops the last action of every window not in alive, the windows that still exist.
    public func prune(alive: Set<WindowID>) {
        last = last.filter { alive.contains($0.key) }
    }

    // run applies action name to the window with id window, raised first, or to the focused window
    // when nil, and reports whether anything moved. Nothing runs while the anchor is weighed. On a
    // pin, Maximize lifts or lowers it, a half or a third places it inside its slot, and Restore gives
    // it its whole slot back or else re-moors it. A chain runs its next step.
    @discardableResult
    public func run(_ name: String, window: WindowID? = nil) -> Bool {
        if name == Keymaps.menuName || name == Keymaps.stripsName {
            return extra.run(name, window)
        }
        guard !anchors.choices.paused, platform.windows.ready else { return false }
        if let window {
            platform.windows.raise(window)
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
            log("chain \(title): no such chain")
            return false
        }
        let window = window ?? platform.windows.scan(platform.screens.current(), full: false).focused?.id
        let press = chainPress.map { $0.name == title && $0.window == window ? $0.press + 1 : 0 } ?? 0
        chainPress = (title, window, press)
        guard let step = chain.step(press: press) else {
            log("chain \(title): no steps")
            return false
        }
        return perform(step, window: window)
    }

    // perform applies action name, which is not a chain, to the window with id window, or to the
    // focused window when nil. Actions on the front app act on the front app, and the routed actions
    // go to the platform.
    private func perform(_ name: String, window: WindowID? = nil) -> Bool {
        if routed(name) {
            return extra.run(name, window)
        }
        if Keymaps.windowNames.contains(name) {
            return frontApp(name)
        }
        let screens = platform.screens.current()
        guard let w = subject(window, screens: screens), !platform.windows.refused.contains(w.id) else {
            log("\(name): no focused window Moorings can move")
            return false
        }
        guard apply(name, to: w, screens: screens) else { return false }
        if anchors.choices.behavior.moveCursor, let f = platform.windows.frame(w.id) {
            platform.warpCursor(Point(x: f.x + f.w / 2, y: f.y + f.h / 2))
        }
        return true
    }

    // subject returns the window with id window, or the focused window when nil, read alone when the
    // platform can and it belongs to no anchored app, and scanned otherwise.
    private func subject(_ window: WindowID?, screens: Screens) -> WindowInfo? {
        if let alone = read(window, screens), !anchors.pins().contains(where: { $0.bundle == alone.bundle }) {
            return alone
        }
        let scan = platform.windows.scan(screens, full: false)
        return window.flatMap { id in scan.windows.first { $0.id == id } } ?? scan.focused
    }

    // frontApp runs a window action on the focused app's windows: bring its next or previous window
    // forward, minimize or close the focused one, or minimize or close every other one. None moves a
    // frame. Anchored windows are left alone, except that close-window closes one as its close button
    // would.
    private func frontApp(_ name: String) -> Bool {
        let scan = platform.windows.scan(platform.screens.current(), full: true)
        guard let w = scan.focused else {
            log("\(name): no focused window")
            return false
        }
        let mine = scan.windows.filter { $0.bundle == w.bundle && !$0.isFilePanel }
        switch name {
        case "focus-next-window", "focus-previous-window":
            guard let next = Tile.neighbor(mine.map(\.id), of: w.id, forward: name == "focus-next-window") else {
                log("\(name): the front app has no other window")
                return false
            }
            platform.windows.raise(next)
            return true
        case "close-window":
            platform.windows.close(w.id)
            return true
        case "minimize-window":
            guard !anchors.pinned(w) else {
                log("the window is pinned: window actions leave pins alone")
                return false
            }
            platform.windows.minimize(w.id)
            return true
        default:
            let others = mine.filter { $0.id != w.id && !anchors.pinned($0) }
            for o in others {
                if name == "minimize-others" {
                    platform.windows.minimize(o.id)
                } else {
                    platform.windows.close(o.id)
                }
            }
            return !others.isEmpty
        }
    }

    // apply applies action name to window w on the screen at index, its own screen when nil, and
    // reports whether it moved.
    @discardableResult
    public func apply(_ name: String, to w: WindowInfo, screens: Screens, index: Int? = nil) -> Bool {
        guard !screens.full.isEmpty else { return false }
        if anchors.pinned(w) {
            switch name {
            case "maximize":
                anchors.toggleLift(w)
                if anchors.isLifted(w.id) {
                    platform.windows.raise(w.id)
                }
                wake()
                moor()
                return true
            case "restore":
                if !anchors.clearPart(w.id) {
                    anchors.remoor(w.id)
                }
                last[w.id] = nil
                wake()
                moor()
                return true
            default:
                if placeInSlot(name, w) {
                    return true
                }
                log("the window is pinned: window actions leave pins alone")
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
            move(w.id, to: f)
            wake()
            return true
        }
        if name == "undo-move" || name == "redo-move" {
            last[w.id] = nil
            let f = name == "undo-move" ? anchors.history.undo(w.id, current: w.frame)
                : anchors.history.redo(w.id, current: w.frame)
            guard let f else {
                log("\(name): nothing to step to for this window")
                return false
            }
            move(w.id, to: f)
            wake()
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
                platform.windows.minimize(w.id)
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

    // placeInSlot moves the slot window w to the part of its slot position action name gives and
    // holds it there, and reports whether it did. It needs slotStacks on, a fixed position such as a
    // half or a third, and w held in the last pass. A repeat press steps the position's cycle.
    private func placeInSlot(_ name: String, _ w: WindowInfo) -> Bool {
        guard anchors.choices.slotStacks, Geometry.cells[Geometry.aliases[name] ?? name] != nil,
              !Actions.maximizers.contains(name) else { return false }
        let area = anchors.actionArea(w.id, else: w.frame)
        let press = last[w.id].map { $0.name == name && Actions.near(w.frame, $0.frame) ? $0.press + 1 : 1 } ?? 1
        guard let f = Geometry.cycle(name, press, area, w.frame, gap: anchors.choices.gapPx),
              anchors.holdPart(w.id, name, f) else { return false }
        move(w.id, to: f)
        last[w.id] = LastPress(name: name, press: press, frame: platform.windows.frame(w.id) ?? f)
        wake()
        return true
    }

    // applyFrame raises the window with id and moves it to frame as a placement restore can undo, and
    // reports whether it moved. Pinned and fullscreen windows stay put.
    @discardableResult
    public func applyFrame(_ frame: Frame, to id: WindowID) -> Bool {
        guard !anchors.choices.paused, platform.windows.ready else { return false }
        guard let w = platform.windows.scan(platform.screens.current(), full: true).windows.first(where: { $0.id == id }),
              !anchors.pinned(w), !w.isFullScreen
        else { return false }
        platform.windows.raise(id)
        chainPress = nil
        return place(w, at: frame, press: 1, name: "grid")
    }

    // area returns the area actions on w use on its own screen.
    public func area(for w: WindowInfo, screens: Screens) -> Frame {
        guard !screens.full.isEmpty else { return w.frame }
        let t = target(for: w, screens: screens)
        return Actions.area(t, t.index, anchors.choices.behavior)
    }

    // move places the window with id at frame, as a restore or a step back does, with no animation.
    private func move(_ id: WindowID, to frame: Frame) {
        platform.windows.move(id, to: frame, from: nil, behavior: anchors.choices.behavior)
    }

    // place moves w to frame and records it as press of action name, so a repeat press steps on.
    private func place(_ w: WindowInfo, at frame: Frame, press: Int, name: String) -> Bool {
        anchors.save(w)
        platform.windows.move(w.id, to: frame, from: w.frame, behavior: anchors.choices.behavior)
        let landed = platform.windows.frame(w.id) ?? frame
        last[w.id] = LastPress(name: name, press: press, frame: landed)
        self.landed(w.id, landed)
        return true
    }

    // target returns the screens an action on w may use, with w on the screen at index, its own
    // screen when index is nil or names a display that is gone.
    private func target(for w: WindowInfo, screens: Screens, index: Int? = nil) -> ActionTarget {
        let areas = screens.usable.indices.map { i in
            i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
        }
        let quirks = platform.screens.quirks(screens)
        let index = index.flatMap { screens.full.indices.contains($0) ? $0 : nil } ?? screens.index(w.frame) ?? 0
        return ActionTarget(screens: screens.full, areas: areas, index: index,
                            notched: quirks.notched, staged: quirks.staged, stageOnRight: quirks.stageOnRight)
    }

    // frame returns the frame action name gives w on the screen at index, its own screen when nil,
    // the press count, and the action the result counts as, without moving it. A fill stops at the
    // other windows on screen.
    public func frame(
        _ name: String, for w: WindowInfo, screens: Screens, index: Int? = nil
    ) -> (Frame?, press: Int, name: String) {
        guard !screens.full.isEmpty else { return (nil, 0, name) }
        let target = target(for: w, screens: screens, index: index)
        if Actions.fillNames.contains(name) {
            let area = Actions.area(target, target.index, anchors.choices.behavior)
            let others = platform.windows.scan(screens, full: true).windows.filter { $0.id != w.id }.map(\.frame)
            let f = Geometry.fill(w.frame, name == "fill-left" ? .left : .right, area: area, others: others,
                                  gap: anchors.choices.gapPx)
            return (f == w.frame ? nil : f, 1, name)
        }
        return Actions.frame(name, cur: w.frame, target: target, gap: anchors.choices.gapPx,
                             sizes: Bindings(anchors.choices).specs, last: last[w.id],
                             behavior: anchors.choices.behavior)
    }

    // preview returns where action name would put w without moving it, for a drag's footprint: nil on
    // a pin or a full-screen window and for the actions that land on no frame of their own, restore,
    // undo and redo, the arrows and the fills.
    public func preview(_ name: String, for w: WindowInfo, screens: Screens, index: Int? = nil) -> Frame? {
        guard !anchors.pinned(w), !w.isFullScreen, !["restore", "undo-move", "redo-move"].contains(name),
              !Actions.arrowNames.contains(name), !Actions.fillNames.contains(name) else { return nil }
        return frame(name, for: w, screens: screens, index: index).0
    }

    // placed returns the frame the last action gave the window with id, nil when none has.
    public func placed(_ id: WindowID) -> Frame? {
        last[id]?.frame
    }

    // unsnap gives the dragged window w, now at current, back the size it had before moorings first
    // moved it, with the cursor grab points from its left edge kept over it, and forgets the snap.
    public func unsnap(_ w: WindowInfo, at current: Frame, grab: Double) {
        let saved = anchors.savedFrame(w.id).map { (w: $0.w, h: $0.h) }
        guard let size = Behavior.unsnapSize(anchors.choices.behavior, wasSnapped: true, saved: saved, current: current)
        else { return }
        let f = Behavior.unsnapFrame(current, size: size, grab: grab)
        if f.x == current.x {
            platform.windows.resize(w.id, w: f.w, h: f.h)
        } else {
            move(w.id, to: f)
        }
        _ = anchors.restore(w.id)
        last[w.id] = nil
    }

    // titleBar maximizes or restores w after a double-click on its title bar.
    public func titleBar(_ w: WindowInfo, screens: Screens) {
        apply(Behavior.titleBarAction(last: last[w.id], frame: w.frame), to: w, screens: screens)
    }
}
