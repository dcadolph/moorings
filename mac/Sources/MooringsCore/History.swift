// History keeps, per window, the frames moorings moved it away from, so undo-move steps back
// through them and redo-move steps forward again. Each window keeps up to depth frames, and only
// the windows touched most recently are kept.
public struct History: Sendable {
    // depth is how many frames each window keeps to step back through.
    public static let depth = 10
    // windows is how many windows keep a history.
    public static let windows = 64

    // back maps each window to the frames to undo to, oldest first.
    var back: [WindowID: [Frame]] = [:]
    // forward maps each window to the frames to redo to, nearest last.
    var forward: [WindowID: [Frame]] = [:]
    // touched lists the windows by when their history last changed, oldest first.
    var touched: [WindowID] = []

    // init builds an empty history.
    public init() {}

    // record notes that the window with id is about to move away from frame. A frame equal to the
    // last one recorded is not recorded twice, and a new move drops what redo had.
    public mutating func record(_ id: WindowID, from frame: Frame) {
        forward[id] = nil
        var list = back[id] ?? []
        if let top = list.last, Self.same(top, frame) {
            return
        }
        list.append(frame)
        back[id] = Array(list.suffix(Self.depth))
        touch(id)
    }

    // undo returns the frame the window with id was in before its last recorded move, nil when there
    // is none, and keeps current for redo.
    public mutating func undo(_ id: WindowID, current: Frame) -> Frame? {
        guard var list = back[id], let f = list.popLast() else { return nil }
        back[id] = list.isEmpty ? nil : list
        forward[id, default: []].append(current)
        touch(id)
        return f
    }

    // redo returns the frame the window with id was in before its last undo, nil when there is none,
    // and keeps current for undo.
    public mutating func redo(_ id: WindowID, current: Frame) -> Frame? {
        guard var list = forward[id], let f = list.popLast() else { return nil }
        forward[id] = list.isEmpty ? nil : list
        back[id, default: []].append(current)
        back[id] = Array(back[id, default: []].suffix(Self.depth))
        touch(id)
        return f
    }

    // touch marks the window with id as the most recently changed and forgets the oldest windows
    // past the limit.
    private mutating func touch(_ id: WindowID) {
        touched.removeAll { $0 == id }
        touched.append(id)
        while touched.count > Self.windows {
            let old = touched.removeFirst()
            back[old] = nil
            forward[old] = nil
        }
    }

    // same reports whether a and b are within a point of each other on every edge.
    static func same(_ a: Frame, _ b: Frame) -> Bool {
        abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.w - b.w) <= 1 && abs(a.h - b.h) <= 1
    }
}
