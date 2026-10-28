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

// ZoomFill records a green button fill: where it put the window and where the window was before.
struct ZoomFill: Equatable {
    // at is the frame the fill left the window at.
    var at: Frame
    // from is the frame the window had just before the fill.
    var from: Frame
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

    // doubt lowers the floor of w on each axis w is seen smaller than it, since w just showed it can
    // be that small. This undoes a size read while an app was still resizing itself.
    func doubt(_ w: WindowInfo) {
        guard var fl = floors[w.id] else { return }
        if w.frame.w < fl.w - Self.tolerance {
            fl.w = w.frame.w
        }
        if w.frame.h < fl.h - Self.tolerance {
            fl.h = w.frame.h
        }
        floors[w.id] = fl
    }

    // cap keeps the floor of the free window with id inside channel ch, so no floor holds it past
    // the channel.
    func cap(_ id: WindowID, _ ch: Frame) {
        guard var fl = floors[id] else { return }
        fl.w = min(fl.w, ch.w)
        fl.h = min(fl.h, ch.h)
        floors[id] = fl
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
        // Only an axis the window refused is learned, so a slot's own size never becomes a minimum.
        let prior = floors[move.id]
        floors[move.id] = Floor(w: got.w > move.frame.w + Self.tolerance ? got.w : prior?.w ?? 0,
                                h: got.h > move.frame.h + Self.tolerance ? got.h : prior?.h ?? 0)
        let want = fit(move.id, move.target, move.anchor)
        if Actions.near(got, want, tolerance: Self.tolerance) {
            return nil
        }
        at = want
        return Move(id: move.id, frame: want, target: move.target, anchor: move.anchor)
    }

    // unread forgets where move put a pin when its frame could not be read back, so the next pass
    // places it again rather than releasing it against a frame that was never confirmed.
    public func unread(_ move: Move) {
        if let p = placed[move.id], Actions.near(p.target, move.target, tolerance: Self.tolerance) {
            placed[move.id] = nil
        }
    }

    // cacheZoom keeps the green button rect of w as it will sit with w at frame.
    func cacheZoom(_ w: WindowInfo, _ frame: Frame, free: Bool) {
        let rect = w.zoomRect.map {
            Frame(x: $0.x + frame.x - w.frame.x, y: $0.y + frame.y - w.frame.y, w: $0.w, h: $0.h)
        }
        zoom[w.id] = ZoomSpot(frame: frame, rect: rect, free: free)
    }

    // moorPin places pinned window w at target, or releases it when the owner has moved it since
    // moorings last left it. A pin on the frame moorings last asked for is where moorings put it, even
    // when the read-back caught it partway through its own animation.
    func moorPin(_ w: WindowInfo, _ target: Frame, _ anchor: Edges) -> Move? {
        var last = placed[w.id]
        if let p = last, Actions.near(w.frame, p.target, tolerance: Self.tolerance)
            || Actions.near(w.frame, fit(w.id, p.target, anchor), tolerance: Self.tolerance) {
            last?.at = w.frame
            placed[w.id]?.at = w.frame
        }
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

    // readBack returns the frame the pin with id was read back at after moorings last placed it, or nil.
    public func readBack(_ id: WindowID) -> Frame? {
        placed[id]?.at
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

    // save records w's frame once, before Fill, Tidy or a window action first moves it, and adds it
    // to the window's history on every move.
    public func save(_ w: WindowInfo) {
        history.record(w.id, from: w.frame)
        if saved[w.id] == nil {
            saved[w.id] = w.frame
        }
        clamped[w.id] = nil
    }

    // savedFrame returns the frame the window with id had before moorings first moved it, nil when
    // there is none, and keeps it.
    public func savedFrame(_ id: WindowID) -> Frame? {
        saved[id]
    }

    // restore returns the frame the window with id had before moorings first moved it, and forgets
    // it, or nil when there is none.
    public func restore(_ id: WindowID) -> Frame? {
        guard let f = saved.removeValue(forKey: id) else { return nil }
        clamped[id] = nil
        return f
    }

    // canUndo reports whether a fill, tidy or window action has moved anything since the last undo.
    public var canUndo: Bool { !saved.isEmpty }

    // undo returns where every window a fill, tidy or window action moved was before its first move,
    // and forgets them all.
    public func undo() -> [WindowID: Frame] {
        let out = saved
        saved = [:]
        clamped = clamped.filter { out[$0.key] == nil }
        return out
    }

    // markFilled records that a green button click filled the channel with the window with id, moving
    // it from from to frame.
    public func markFilled(_ id: WindowID, _ frame: Frame, from: Frame) {
        filled[id] = ZoomFill(at: frame, from: from)
    }

    // unfill returns the frame the window with id had just before its last green button fill, and
    // forgets the fill, or nil when there is none. A saved frame equal to it is forgotten too, since
    // the window is back where moorings first found it.
    public func unfill(_ id: WindowID) -> Frame? {
        guard let f = filled.removeValue(forKey: id) else { return nil }
        if let s = saved[id], Actions.near(s, f.from, tolerance: Self.tolerance) {
            saved[id] = nil
            clamped[id] = nil
        }
        return f.from
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
                if let f = filled[id], Actions.near(c.frame, f.at, tolerance: Self.tolerance) {
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

// SharedEdge is an edge two windows share that a drag moves for both: a sits left of or above b.
public struct SharedEdge: Equatable, Sendable {
    // a is the index of the window left of or above the edge.
    public var a: Int
    // b is the index of the window right of or below the edge.
    public var b: Int
    // vertical reports whether the edge runs top to bottom, so a drag moves it left and right.
    public var vertical: Bool
}

// SharedEdges finds an edge two windows share under the pointer and resizes both as it moves, as a
// divider between panes does.
public enum SharedEdges {
    // touch is how far apart in points two edges may be and still count as shared.
    public static let touch = 4.0
    // grab is how far in points from the edge a drag may start.
    public static let grab = 8.0
    // minimum is the smallest width or height in points a shared edge drag leaves a window.
    public static let minimum = 160.0

    // find returns the shared edge within grab of p among frames, front-most first. The pair whose
    // front window comes first wins, and the edge counts only where the two windows overlap along it.
    public static func find(at p: Point, frames: [Frame]) -> SharedEdge? {
        for (i, f) in frames.enumerated() {
            for (j, g) in frames.enumerated() where j != i {
                if let e = edge(f, i, g, j, at: p) {
                    return e
                }
            }
        }
        return nil
    }

    // edge returns the edge f and g share near p with f left of or above g, nil when they share none.
    static func edge(_ f: Frame, _ i: Int, _ g: Frame, _ j: Int, at p: Point) -> SharedEdge? {
        let right = f.x + f.w
        if abs(right - g.x) <= touch, abs(p.x - (right + g.x) / 2) <= grab {
            let top = max(f.y, g.y)
            let bottom = min(f.y + f.h, g.y + g.h)
            if bottom > top, p.y >= top, p.y <= bottom {
                return SharedEdge(a: i, b: j, vertical: true)
            }
        }
        let low = f.y + f.h
        if abs(low - g.y) <= touch, abs(p.y - (low + g.y) / 2) <= grab {
            let left = max(f.x, g.x)
            let far = min(f.x + f.w, g.x + g.w)
            if far > left, p.x >= left, p.x <= far {
                return SharedEdge(a: i, b: j, vertical: false)
            }
        }
        return nil
    }

    // resize returns a and b after the shared edge between them moved by delta points, right or
    // down when positive, keeping the space between them and each far edge where it was. Neither
    // window gets narrower or shorter than minimum.
    public static func resize(_ a: Frame, _ b: Frame, vertical: Bool, delta: Double) -> (Frame, Frame) {
        var a = a
        var b = b
        if vertical {
            let d = min(max(delta, minimum - a.w), b.w - minimum)
            a.w += d
            b.x += d
            b.w -= d
        } else {
            let d = min(max(delta, minimum - a.h), b.h - minimum)
            a.h += d
            b.y += d
            b.h -= d
        }
        return (a, b)
    }
}
