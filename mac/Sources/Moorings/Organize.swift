import AppKit
import os

import MooringsCore

// NamePrompt asks for the name of a workspace or a profile.
@MainActor
enum NamePrompt {
    // ask asks for a name, nil when canceled or empty. The default wording names a workspace.
    static func ask(
        _ title: String = "Save workspace",
        _ info: String = "Name this layout: the slots, widths, heights and where each free window sits."
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// Tiler keeps the free windows of each display in the tiling mode's layout as windows come and go,
// and runs the tiling actions. A window the owner drags or resizes floats until a mode is chosen
// again. On the ultrawide it tiles the channel, so push back never has a tiled window to move.
@MainActor
final class Tiler {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes what tiling did and why an action did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "tiling")
    // order is the tiling order of the tiled windows, main window first.
    private var order: [WindowID] = []
    // assigned maps each tiled window to the frame it was last given and when.
    private var assigned: [WindowID: (frame: Frame, at: Double)] = [:]
    // floated holds the windows the owner moved out of the layout.
    private var floated: Set<WindowID> = []
    // released is when the primary mouse button last came up.
    private var released = 0.0

    // init builds a tiler for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // anchors is the layout the tiler reads.
    private var anchors: Anchors { app.anchors }

    // mouseUp records a mouse up, so a tiled window found off its frame after it was moved by hand.
    func mouseUp() {
        released = AppDelegate.now
    }

    // tileable reports whether w joins the layout: not anchored, fullscreen, a file panel, stashed or
    // cast off.
    private func tileable(_ w: WindowInfo) -> Bool {
        !w.isFilePanel && !w.isFullScreen && !anchors.pinned(w) && !anchors.stashed.contains(w.id)
            && !anchors.isCastOff(w.id)
    }

    // pass lays out list, the windows on screen front-most first, after a moor pass. Each window gets
    // a frame only when its frame in the layout changed, so an app that keeps its own size is left
    // alone, and a window found off its frame after a mouse up floats. It does nothing while tiling
    // is off, while paused, or while the mouse button is down.
    func pass(_ list: [WindowInfo], screens: Screens, mouseHeld: Bool) {
        let tiling = anchors.choices.tiling
        guard tiling.mode != .off, !anchors.choices.paused, !mouseHeld else { return }
        let now = AppDelegate.now
        let free = list.filter(tileable)
        floated.formIntersection(free.map(\.id))
        order = Tiling.order(order, free.map(\.id).filter { !floated.contains($0) })
        assigned = assigned.filter { id, _ in order.contains(id) }
        let byID = Dictionary(free.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in screens.full.indices {
            let ids = order.filter { byID[$0].flatMap { screens.index($0.frame) } == i }
            let frames = Tiling.layout(tiling.mode, app.organizer.area(screens, i), ids.count, ratio: tiling.ratio,
                                       gap: anchors.choices.gapPx)
            for (id, target) in zip(ids, frames) {
                guard let w = byID[id] else { continue }
                if let a = assigned[id], Actions.near(a.frame, target, tolerance: Actions.tolerance) {
                    if released > a.at, !Actions.near(w.frame, a.frame, tolerance: Actions.tolerance) {
                        floated.insert(id)
                        order.removeAll { $0 == id }
                        assigned[id] = nil
                        logger.notice("window \(id) moved by hand: floating until a mode is chosen again")
                    }
                    continue
                }
                if !Actions.near(w.frame, target, tolerance: Actions.tolerance) {
                    anchors.save(w)
                    app.windows.move(id, to: target)
                }
                assigned[id] = (target, now)
            }
        }
    }

    // run applies tiling action name and reports whether it did anything. Choosing a mode, even the
    // one in use, brings floated windows back into the layout.
    func run(_ name: String) -> Bool {
        if let mode = Tiling.mode(name) {
            choose(mode)
            return true
        }
        switch name {
        case Tiling.cycleName:
            choose(Tiling.next(anchors.choices.tiling.mode))
            return true
        case "grow-main", "shrink-main":
            let was = anchors.choices.tiling.ratio
            anchors.choices.tiling.ratio = Tiling.resized(was, grow: name == "grow-main")
            guard anchors.choices.tiling.ratio != was else { return false }
            app.save()
            return true
        default:
            guard let dir = Tiling.direction(name) else { return false }
            return Tiling.focusNames.contains(name) ? focus(dir) : swap(dir)
        }
    }

    // choose sets mode, forgets the floated windows and every frame given, and lays out again.
    private func choose(_ mode: TileMode) {
        anchors.choices.tiling.mode = mode
        floated = []
        assigned = [:]
        app.save()
        app.notify("Tiling", mode == .off ? "Off. Windows stay where they are." : "\(Keymaps.label(Tiling.modePrefix + mode.rawValue)).")
    }

    // neighbor returns the focused window and its nearest neighbor in dir among the windows on
    // screen, leaving out anchored windows when anchored is false.
    private func neighbor(_ dir: TileDirection, anchored: Bool) -> (WindowInfo, WindowInfo)? {
        let scan = app.windows.scan(Screens.current())
        guard let me = scan.focused else {
            logger.notice("no focused window")
            return nil
        }
        let pool = scan.windows.filter { !$0.isFilePanel && !$0.isFullScreen && (anchored || !anchors.pinned($0)) }
        guard let i = pool.firstIndex(where: { $0.id == me.id }),
              let k = Tiling.toward(dir, from: i, frames: pool.map(\.frame))
        else {
            logger.notice("no window \(dir.rawValue, privacy: .public) of the focused one")
            return nil
        }
        return (me, pool[k])
    }

    // focus brings the nearest window in dir to the front.
    private func focus(_ dir: TileDirection) -> Bool {
        guard let (_, other) = neighbor(dir, anchored: true) else { return false }
        app.windows.raise(other.id)
        return true
    }

    // swap trades the focused window's place with its nearest neighbor in dir: their places in the
    // layout while both are tiled, their frames otherwise. Anchored windows never swap.
    private func swap(_ dir: TileDirection) -> Bool {
        guard let (me, other) = neighbor(dir, anchored: false) else { return false }
        if anchors.choices.tiling.mode != .off, order.contains(me.id), order.contains(other.id) {
            order = Tiling.swapped(order, me.id, other.id)
            assigned[me.id] = nil
            assigned[other.id] = nil
            app.moor()
            return true
        }
        anchors.save(me)
        anchors.save(other)
        app.windows.move(me.id, to: other.frame)
        app.windows.move(other.id, to: me.frame)
        app.wake()
        return true
    }
}
