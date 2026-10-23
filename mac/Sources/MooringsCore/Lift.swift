import Foundation

// PinPlacement records where a pin was last put: the frame it was given, where it ended up, and when.
struct PinPlacement: Equatable {
    // target is the frame the pin was given.
    var target: Frame
    // at is the frame the pin ended up at.
    var at: Frame
    // t is when the pin was put there.
    var t: Double
}

// ZoomSpot is a window's green button as of the last pass.
struct ZoomSpot: Equatable {
    // frame is the window's frame when the rect was taken.
    var frame: Frame
    // rect is the green button rect, nil when the window reported none.
    var rect: Frame?
    // free reports whether the window is free rather than pinned.
    var free: Bool
}

// Floor is the smallest size a window was seen to keep.
struct Floor: Equatable {
    // w is the smallest width.
    var w: Double
    // h is the smallest height.
    var h: Double
}

// ZoomAction is what a click on a green button does.
public enum ZoomAction: Equatable, Sendable {
    // lift lifts the pin over its strip and the channel.
    case lift(WindowID)
    // lower puts a lifted pin back in its slot.
    case lower(WindowID)
    // remoor puts a released pin back in its slot.
    case remoor(WindowID)
    // fill fills the channel with a free window.
    case fill(WindowID)
    // restore puts a free window back where it was before its last fill.
    case restore(WindowID)
}

// Anchors gains lifting pins, releasing pins the owner moves, learning sizes windows keep, the
// green button and native fullscreen.
extension Anchors {
    // releaseGrace is how many seconds after a move a pin may settle on its own before a change is
    // taken as the owner moving it.
    static let releaseGrace = 2.0
    // pendingSeconds is how long a window leaving fullscreen waits for its fill.
    static let pendingSeconds = 5.0

    // fit grows frame to the smallest size the window with id is known to keep. The edges named in
    // anchor stay put.
    func fit(_ id: WindowID, _ frame: Frame, _ anchor: Edges) -> Frame {
        guard let fl = floors[id] else { return frame }
        var f = frame
        if fl.w > f.w {
            if anchor.right {
                f.x += f.w - fl.w
            }
            f.w = fl.w
        }
        if fl.h > f.h {
            if anchor.bottom {
                f.y += f.h - fl.h
            }
            f.h = fl.h
        }
        return f
    }

    // measure records the widest floor among the pinned windows on each side.
    func measure(_ windows: [WindowInfo], _ pins: [Pin]) {
        var mins: [Side: Double] = [:]
        var by: [Side: String] = [:]
        for w in windows {
            guard let pin = pins.first(where: { $0.bundle == w.bundle }), let fl = floors[w.id],
                  fl.w > (mins[pin.slot.side] ?? 0)
            else { continue }
            mins[pin.slot.side] = fl.w
            by[pin.slot.side] = w.bundle
        }
        minPoints = mins
        minBy = by
    }

    // minWidth returns the widest size a pin on side is known to keep, zero when none.
    public func minWidth(_ side: Side) -> Double {
        minPoints[side] ?? 0
    }

    // landed takes the frame a window ended up at after move. When the window kept a larger size
    // than it was given, the size is learned and a move that lines its anchored edges up with the
    // target is returned.
    public func landed(_ move: Move, got: Frame) -> Move? {
        guard !move.exitFullScreen else { return nil }
        var at = got
        defer {
            if var p = placed[move.id], Actions.near(p.target, move.target, tolerance: Self.tolerance) {
                p.at = at
                placed[move.id] = p
            }
        }
        if got.w <= move.frame.w + Self.tolerance && got.h <= move.frame.h + Self.tolerance {
            return nil
        }
        floors[move.id] = Floor(w: max(got.w, move.frame.w), h: max(got.h, move.frame.h))
        let want = fit(move.id, move.target, move.anchor)
        if Actions.near(got, want, tolerance: Self.tolerance) {
            return nil
        }
        at = want
        return Move(id: move.id, frame: want, target: move.target, anchor: move.anchor)
    }

    // cacheZoom keeps the green button rect of w as it will sit with w at frame.
    func cacheZoom(_ w: WindowInfo, _ frame: Frame, free: Bool) {
        let rect = w.zoomRect.map {
            Frame(x: $0.x + frame.x - w.frame.x, y: $0.y + frame.y - w.frame.y, w: $0.w, h: $0.h)
        }
        zoom[w.id] = ZoomSpot(frame: frame, rect: rect, free: free)
    }

    // moorPin places pinned window w at target, or releases it when the owner has moved it since
    // moorings last left it.
    func moorPin(_ w: WindowInfo, _ target: Frame, _ anchor: Edges) -> Move? {
        let last = placed[w.id]
        if let last, now - last.t > Self.releaseGrace, !Actions.near(w.frame, last.at, tolerance: Self.tolerance),
           !released.contains(w.id) {
            released.insert(w.id)
            lifted.remove(w.id)
            justReleased.append(w.id)
        }
        if released.contains(w.id) {
            cacheZoom(w, w.frame, free: false)
            return nil
        }
        let move = place(w, target, anchor)
        let at = move?.frame ?? w.frame
        if last == nil || !Actions.near(last!.at, at, tolerance: Self.tolerance)
            || !Actions.near(last!.target, target, tolerance: Self.tolerance) {
            placed[w.id] = PinPlacement(target: target, at: at, t: now)
        }
        cacheZoom(w, at, free: false)
        return move
    }

    // leaveFullScreen asks fullscreen window w to leave native fullscreen, once per pendingSeconds.
    func leaveFullScreen(_ w: WindowInfo) -> Move? {
        if let started = pendingFill[w.id], now - started <= Self.pendingSeconds {
            return nil
        }
        pendingFill[w.id] = now
        return Move(id: w.id, frame: w.frame, exitFullScreen: true)
    }

    // isLifted reports whether the pin with id is lifted.
    public func isLifted(_ id: WindowID) -> Bool {
        lifted.contains(id)
    }

    // isReleased reports whether moorings let the pin with id go after the owner moved it.
    public func isReleased(_ id: WindowID) -> Bool {
        released.contains(id)
    }

    // target returns the frame moorings last gave the pin with id, or nil.
    public func target(_ id: WindowID) -> Frame? {
        placed[id]?.target
    }

    // toggleLift lifts pinned window w over its strip and the channel, or lowers it back into its
    // slot, and reports whether w is a pin.
    @discardableResult
    public func toggleLift(_ w: WindowInfo) -> Bool {
        guard pinned(w) else { return false }
        toggleLift(id: w.id)
        return true
    }

    // toggleLift lifts or lowers the pin with id.
    public func toggleLift(id: WindowID) {
        if lifted.remove(id) == nil {
            lifted.insert(id)
        }
        released.remove(id)
        placed[id] = nil
    }

    // remoor puts a released or lifted pin back in its slot on the next pass.
    public func remoor(_ id: WindowID) {
        lifted.remove(id)
        released.remove(id)
        placed[id] = nil
    }

    // screensChanged forgets where pins were placed, so pins a display change moved are re-moored
    // rather than released.
    public func screensChanged() {
        placed = [:]
    }

    // save records w's frame once, before Fill, Tidy or a window action first moves it.
    public func save(_ w: WindowInfo) {
        if saved[w.id] == nil {
            saved[w.id] = w.frame
        }
        clamped[w.id] = nil
    }

    // restore returns the frame the window with id had before moorings first moved it, and forgets
    // it, or nil when there is none.
    public func restore(_ id: WindowID) -> Frame? {
        guard let f = saved.removeValue(forKey: id) else { return nil }
        clamped[id] = nil
        return f
    }

    // markFilled records that a green button click filled the channel with the window with id, now
    // at frame, or forgets the fill when frame is nil.
    public func markFilled(_ id: WindowID, _ frame: Frame?) {
        filled[id] = frame
    }

    // covered reports whether a window in front of the window with id holds point p, so a click
    // there belongs to that window. front lists the on-screen windows front-most first.
    public static func covered(_ id: WindowID, _ p: Point, front: [(id: WindowID, frame: Frame)]) -> Bool {
        for w in front {
            if w.id == id {
                return false
            }
            if inside(p, w.frame) {
                return true
            }
        }
        return false
    }

    // inside reports whether point p lies in rect r.
    static func inside(_ p: Point, _ r: Frame) -> Bool {
        p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
    }

    // zoomClick returns what a click at p on a green button does, or nil when the click is not on a
    // button moorings handles and passes on. A window covering the button keeps its click, and so
    // does an Option-click on a free window, which macOS treats as zoom.
    public func zoomClick(_ p: Point, option: Bool, front: [(id: WindowID, frame: Frame)]) -> ZoomAction? {
        guard !choices.paused else { return nil }
        let free = choices.fullscreenFills && !option
        for (id, c) in zoom.sorted(by: { $0.key < $1.key }) {
            guard let r = c.rect, free || !c.free, Self.inside(p, r), !Self.covered(id, p, front: front) else {
                continue
            }
            if c.free {
                if let f = filled[id], Actions.near(c.frame, f, tolerance: Self.tolerance) {
                    return .restore(id)
                }
                return .fill(id)
            }
            if released.contains(id) {
                return .remoor(id)
            }
            return lifted.contains(id) ? .lower(id) : .lift(id)
        }
        return nil
    }
}

// Point is a position in global top-left coordinates.
public struct Point: Equatable, Sendable {
    // x is the horizontal position.
    public var x: Double
    // y is the vertical position.
    public var y: Double

    // init builds a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
