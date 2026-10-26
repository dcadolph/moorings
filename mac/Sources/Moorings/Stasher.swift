import AppKit
import os

import MooringsCore

// Stasher parks windows at a screen edge with a sliver left on screen. Resting the pointer on the
// sliver slides the window out, and moving the pointer off it slides the window back. A click in a
// slid-out window, the stash action again, or unstash-all ends the stash. The pointer is read only
// while a window is stashed, and stashed windows go back where they were when Moorings quits.
@MainActor
final class Stasher {
    // tickSeconds is how often the pointer is read while a window is stashed.
    static let tickSeconds = 0.05
    // edgeReach is how close in points to a screen edge a Command-drag must end to stash there.
    static let edgeReach = 2.0

    // Entry is one stashed window and the area it parks in.
    struct Entry {
        // s is the stash.
        var s: Stashed
        // area is the usable area the window parks at the edge of.
        var area: Frame
    }

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why a stash did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "stash")
    // entries lists the stashed windows.
    private(set) var entries: [Entry] = []
    // timer reads the pointer while a window is stashed.
    private var timer: Timer?

    // init builds a stasher for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // run applies a stash action: stash toggles the focused window, unstash-all puts every stashed
    // window back.
    @discardableResult
    func run(_ name: String) -> Bool {
        if name == "unstash-all" {
            let any = !entries.isEmpty
            unstashAll()
            return any
        }
        guard let w = app.windows.scan(Screens.current()).focused else {
            logger.notice("stash: no focused window")
            return false
        }
        if entries.contains(where: { $0.s.id == w.id }) {
            unstash(w.id)
            return true
        }
        return stash(w, edge: nil)
    }

    // stash parks w at edge, or at the nearest edge that can take it when nil, and reports whether it
    // parked. Unstashing puts it back at original, or where it is now when nil. An edge another display touches cannot take it, and on the ultrawide neither can a side
    // with an anchored app, so a stash never covers a strip. A move macOS refuses is undone.
    @discardableResult
    func stash(_ w: WindowInfo, edge: StashEdge?, original: Frame? = nil) -> Bool {
        guard !app.anchors.choices.paused, !app.anchors.pinned(w), !w.isFullScreen else {
            logger.notice("stash: pinned and fullscreen windows are not stashed")
            return false
        }
        let screens = Screens.current()
        guard let i = screens.index(w.frame) else { return false }
        let area = screens.usable[i]
        var blocked: Set<StashEdge> = []
        var span: Frame?
        if i == screens.ultrawide {
            let sides = Set(app.anchors.choices.slots.keys.map(\.side))
            if sides.contains(.left) {
                blocked.insert(.left)
            }
            if sides.contains(.right) {
                blocked.insert(.right)
            }
            span = app.anchors.channel(area)
        }
        let others = screens.full.indices.filter { $0 != i }.map { screens.full[$0] }
        var allowed = Stash.edges(screens.full[i], others: others, blocked: blocked)
        if let edge {
            allowed = allowed.intersection([edge])
        }
        guard var s = Stash.stash(w.id, w.frame, area: area, allowed: allowed, span: span) else {
            logger.notice("stash: no free edge on this display")
            return false
        }
        app.anchors.stashed.insert(w.id)
        app.windows.move(w.id, to: s.hidden)
        guard let landed = app.windows.frame(w.id), Stash.parked(landed, screen: area) else {
            app.anchors.stashed.remove(w.id)
            app.windows.move(w.id, to: w.frame)
            logger.notice("stash: macOS kept the window on screen")
            return false
        }
        s.hidden = landed
        if let original {
            s.original = original
        }
        entries.removeAll { $0.s.id == w.id }
        entries.append(Entry(s: s, area: area))
        startTimer()
        app.wake()
        return true
    }

    // unstash puts the window with id back where it was before the stash.
    func unstash(_ id: WindowID) {
        guard let e = entries.first(where: { $0.s.id == id }) else { return }
        forget(id)
        app.windows.move(id, to: e.s.original)
        app.wake()
    }

    // unstashAll puts every stashed window back where it was.
    func unstashAll() {
        for e in entries {
            unstash(e.s.id)
        }
    }

    // forget ends the stash of the window with id without moving it.
    private func forget(_ id: WindowID) {
        entries.removeAll { $0.s.id == id }
        app.anchors.stashed.remove(id)
        if entries.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    // clicked ends the stash of a slid-out window under p, leaving it where it is. It runs inside the
    // event tap, so it reads only the frames already known.
    func clicked(_ p: CGPoint) {
        for e in entries where e.s.out {
            let f = e.s.shown
            if p.x >= f.x, p.x <= f.x + f.w, p.y >= f.y, p.y <= f.y + f.h {
                forget(e.s.id)
            }
        }
    }

    // dropEdge returns the edge a Command-drag ending at p stashes at: Command held, Command not one of
    // the keys snapping needs, and p within edgeReach of a display's left, right or bottom edge.
    func dropEdge(_ p: CGPoint, flags: CGEventFlags) -> StashEdge? {
        guard flags.contains(.maskCommand), !app.anchors.choices.snapping.snapModifiers.contains("command") else {
            return nil
        }
        let screens = Screens.current()
        guard let f = screens.full.first(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h })
        else { return nil }
        if p.x - f.x <= Self.edgeReach {
            return .left
        }
        if f.x + f.w - 1 - p.x <= Self.edgeReach {
            return .right
        }
        if f.y + f.h - 1 - p.y <= Self.edgeReach {
            return .bottom
        }
        return nil
    }

    // startTimer reads the pointer while a window is stashed.
    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
    }

    // tick slides a stashed window out or back as the pointer asks. A window that has moved since it
    // was parked or slid out was taken by the owner, so its stash ends where it is.
    private func tick() {
        guard !app.anchors.choices.paused else { return }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        let p = Point(x: loc.x, y: primary - loc.y)
        let held = NSEvent.pressedMouseButtons != 0
        let now = AppDelegate.now
        for i in entries.indices.reversed() {
            var e = entries[i]
            let ask = Stash.hover(&e.s, p, screen: e.area, now: now, mouseHeld: held)
            entries[i] = e
            switch ask {
            case .none:
                continue
            case .slideOut:
                guard let f = app.windows.frame(e.s.id), Actions.near(f, e.s.hidden, tolerance: Actions.tolerance)
                else {
                    forget(e.s.id)
                    continue
                }
                entries[i].s.out = true
                entries[i].s.restSince = nil
                slide(e.s.id, from: f, to: e.s.shown)
                app.windows.raise(e.s.id)
            case .slideBack:
                guard let f = app.windows.frame(e.s.id), Actions.near(f, e.s.shown, tolerance: Actions.tolerance)
                else {
                    forget(e.s.id)
                    continue
                }
                entries[i].s.out = false
                slide(e.s.id, from: f, to: e.s.hidden)
            }
        }
    }

    // slide moves the window with id from start to frame, sliding it when animation is on.
    private func slide(_ id: WindowID, from start: Frame, to frame: Frame) {
        let b = app.anchors.choices.behavior
        if b.animate {
            app.windows.slide(id, from: start, to: frame, enhancedUI: b.enhancedUI)
        } else {
            app.windows.move(id, to: frame, enhancedUI: b.enhancedUI)
        }
    }
}
