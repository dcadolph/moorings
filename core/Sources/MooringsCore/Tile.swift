import Foundation

// TileWindow is the part of a window the organize orders need: its ID and frame.
public struct TileWindow: Equatable, Sendable {
    // id is the window's ID, the final tie-break in every order.
    public var id: WindowID
    // frame is the window's current frame.
    public var frame: Frame

    // init builds a tile window.
    public init(id: WindowID, frame: Frame) {
        self.id = id
        self.frame = frame
    }
}

// TileUndo is the snapshot taken before an organize action: where each moved window was, keyed by
// window ID, so Undo tidy and Restore can put it back.
public struct TileUndo: Equatable, Sendable, Codable {
    // frames maps each moved window's ID to the frame it had before the move.
    public var frames: [WindowID: Frame]

    // init builds a snapshot from saved frames.
    public init(frames: [WindowID: Frame] = [:]) {
        self.frames = frames
    }

    // capture snapshots the frames of windows before they move.
    public static func capture(_ windows: [TileWindow]) -> TileUndo {
        var frames: [WindowID: Frame] = [:]
        for w in windows {
            frames[w.id] = w.frame
        }
        return TileUndo(frames: frames)
    }

    // restore returns the saved frame of each window still known, in the order of ids.
    public func restore(_ ids: [WindowID]) -> [(WindowID, Frame)] {
        ids.compactMap { id in frames[id].map { (id, $0) } }
    }
}

extension Frame: Codable {
    private enum CodingKeys: String, CodingKey { case x, y, w, h }

    // init decodes a frame from its four edges.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
            w: try c.decode(Double.self, forKey: .w), h: try c.decode(Double.self, forKey: .h))
    }

    // encode writes the frame's four edges.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .w)
        try c.encode(h, forKey: .h)
    }
}

// StackChoices holds the stacked window choices, each at Rectangle's default.
public struct StackChoices: Equatable, Sendable, Codable {
    // overlapOffset reports whether a window landing on another window's corner shifts clear of it.
    public var overlapOffset: Bool = false
    // overlapOffsetSize is the shift in points per step.
    public var overlapOffsetSize: Double = 11
    // overlapMaxCascade is the most steps a window shifts.
    public var overlapMaxCascade: Int = 1
    // badge reports whether a badge lists the windows stacked at a corner.
    public var badge: Bool = false
    // sameSizeOnly reports whether only windows of the same size count as stacked.
    public var sameSizeOnly: Bool = false

    // init builds stack choices at the defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case overlapOffset, overlapOffsetSize, overlapMaxCascade, badge, sameSizeOnly
    }

    // init decodes stack choices, keeping the default for any field missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overlapOffset = (try? c.decodeIfPresent(Bool.self, forKey: .overlapOffset)) ?? false
        overlapOffsetSize = (try? c.decodeIfPresent(Double.self, forKey: .overlapOffsetSize)) ?? 11
        overlapMaxCascade = (try? c.decodeIfPresent(Int.self, forKey: .overlapMaxCascade)) ?? 1
        badge = (try? c.decodeIfPresent(Bool.self, forKey: .badge)) ?? false
        sameSizeOnly = (try? c.decodeIfPresent(Bool.self, forKey: .sameSizeOnly)) ?? false
    }

    // reach is how far in points a window's top-left corner may sit right of, above or below a
    // stack's corner and still be in the stack: every step the overlap offset can take, plus the
    // rounding tolerance.
    public var reach: Double {
        max(overlapOffsetSize, 1) * Double(min(5, max(1, overlapMaxCascade))) + Actions.tolerance
    }
}

// Tile holds the organize frame math: columns, rows, a grid, a cascade and a mirror. Every function
// is pure.
public enum Tile {
    // names lists the organize actions in menu order.
    public static let names = [
        "tile-columns", "tile-rows", "tile-all", "tile-active-app", "cascade-all", "cascade-active-app",
        "cycle-stacked-windows", "cycle-stacked-windows-backward", "cycle-slot-windows",
        "cycle-slot-windows-backward", "reverse-all",
    ]

    // cascadeStep is how far in points each cascaded window sits from the last.
    public static let cascadeStep = 30.0

    // stackSizeTolerance is how far in points two windows' sizes may differ and still count as the
    // same size, so terminals that round to a character cell stack together.
    public static let stackSizeTolerance = 24.0

    // cornerZone is how far in points right of and below a window's top-left corner the pointer may
    // rest and still ask for the stack badge, before the gap is added.
    public static let cornerZone = 48.0

    // cornerSlack is how far in points left of and above a window's top-left corner the pointer may
    // rest and still count as at that corner.
    public static let cornerSlack = 4.0

    // stack returns the indices of the windows stacked with frames[i], in frames order: the densest
    // cascade cluster holding it. Every origin is tried as the cluster's left corner, a window joins
    // when its origin sits up to the tolerance left of that corner and up to the reach right of,
    // above or below it, and the earliest corner wins a tie. Any size counts unless sameSizeOnly,
    // when only windows within stackSizeTolerance of frames[i]'s size are clustered. It returns an
    // empty list when i is out of range. The stack badge and cycle-stacked-windows both use it, so
    // the badge counts what the shortcut cycles.
    public static func stack(anchorOf i: Int, among frames: [Frame], choices: StackChoices) -> [Int] {
        guard frames.indices.contains(i) else { return [] }
        let me = frames[i]
        let pool = frames.indices.filter { j in
            let f = frames[j]
            return !choices.sameSizeOnly
                || (abs(f.w - me.w) <= stackSizeTolerance && abs(f.h - me.h) <= stackSizeTolerance)
        }
        var best: [Int] = []
        for a in pool {
            let c = cluster(at: frames[a], among: frames, pool: pool, reach: choices.reach)
            if c.count > best.count && c.contains(i) {
                best = c
            }
        }
        return best
    }

    // cluster returns the indices in pool whose origin sits in the cascade box of corner's origin.
    static func cluster(at corner: Frame, among frames: [Frame], pool: [Int], reach: Double) -> [Int] {
        pool.filter { j in
            let dx = frames[j].x - corner.x
            let dy = frames[j].y - corner.y
            return dx >= -Actions.tolerance && dx <= reach && dy >= -reach && dy <= reach
        }
    }

    // hovered returns the index of the front window under p, given frames front to back, when p
    // rests at that window's top-left corner: up to cornerZone plus gap right of and below it, or up
    // to cornerSlack left of and above it. It returns nil anywhere else, including the rest of the
    // window.
    public static func hovered(at p: Point, frames: [Frame], gap: Double) -> Int? {
        guard
            let i = frames.firstIndex(where: { f in
                p.x >= f.x - cornerSlack && p.x < f.x + f.w && p.y >= f.y - cornerSlack && p.y < f.y + f.h
            })
        else { return nil }
        let zone = cornerZone + gap
        return p.x - frames[i].x <= zone && p.y - frames[i].y <= zone ? i : nil
    }

    // handles reports whether name is an organize action.
    public static func handles(_ name: String) -> Bool {
        names.contains(name)
    }

    // neighbor returns the window after current in window number order, or before it when forward
    // is false, wrapping at the ends. Window numbers follow the order windows were made, so repeat
    // presses visit every window, where front to back order would bounce between the front two. It
    // returns nil when current is not in ids or no other window is.
    public static func neighbor(_ ids: [WindowID], of current: WindowID, forward: Bool) -> WindowID? {
        let order = Array(Set(ids)).sorted()
        guard order.count > 1, let at = order.firstIndex(of: current) else { return nil }
        let n = order.count
        return order[((at + (forward ? 1 : -1)) % n + n) % n]
    }

    // columns returns n side by side frames filling area.
    public static func columns(_ area: Frame, _ n: Int, gap: Double = 0) -> [Frame] {
        (0..<max(n, 0)).map { Geometry.part(area, $0, $0 + 1, n, 0, 1, 1, gap: gap) }
    }

    // rows returns n stacked frames filling area.
    public static func rows(_ area: Frame, _ n: Int, gap: Double = 0) -> [Frame] {
        (0..<max(n, 0)).map { Geometry.part(area, 0, 1, 1, $0, $0 + 1, n, gap: gap) }
    }

    // grid returns n frames in a near square grid read left to right, top to bottom. A short last
    // row widens its frames so the area has no hole.
    public static func grid(_ area: Frame, _ n: Int, gap: Double = 0) -> [Frame] {
        guard n > 0 else { return [] }
        let cols = Int(Double(n).squareRoot().rounded(.up))
        let rows = Int((Double(n) / Double(cols)).rounded(.up))
        return (0..<n).map { k in
            let r = k / cols
            let c = k % cols
            let inRow = min(cols, n - r * cols)
            return Geometry.part(area, c, c + 1, inRow, r, r + 1, rows, gap: gap)
        }
    }

    // cascade returns frames for windows of the given frames, back-most first, each stepped down and
    // right from the last. Windows keep their size unless the stack would leave the area, and the
    // step shrinks when many windows would push the stack past half the area.
    public static func cascade(_ area: Frame, _ frames: [Frame], step: Double = cascadeStep) -> [Frame] {
        let n = frames.count
        var step = step
        if n > 1 {
            step = min(step, floor(area.w / 2 / Double(n - 1)), floor(area.h / 2 / Double(n - 1)))
        }
        let off = Double(n - 1) * step
        return frames.enumerated().map { i, f in
            Frame(
                x: area.x + Double(i) * step, y: area.y + Double(i) * step,
                w: min(f.w, area.w - off), h: min(f.h, area.h - off))
        }
    }

    // reverse returns f mirrored left to right across area.
    public static func reverse(_ area: Frame, _ f: Frame) -> Frame {
        Frame(x: area.x + area.w - (f.x - area.x) - f.w, y: f.y, w: f.w, h: f.h)
    }

    // byX orders windows left to right, then top to bottom, then by ID.
    public static func byX(_ a: TileWindow, _ b: TileWindow) -> Bool {
        if a.frame.x != b.frame.x { return a.frame.x < b.frame.x }
        if a.frame.y != b.frame.y { return a.frame.y < b.frame.y }
        return a.id < b.id
    }

    // byY orders windows top to bottom, then left to right, then by ID.
    public static func byY(_ a: TileWindow, _ b: TileWindow) -> Bool {
        if a.frame.y != b.frame.y { return a.frame.y < b.frame.y }
        if a.frame.x != b.frame.x { return a.frame.x < b.frame.x }
        return a.id < b.id
    }

    // tidy sorts the n front-most windows of front, which is front-most first, left to right and
    // returns them with the equal column each takes in area.
    public static func tidy(_ area: Frame, _ front: [TileWindow], _ n: Int, gap: Double = 0)
        -> [(TileWindow, Frame)]
    {
        let list = Array(front.prefix(max(n, 0))).sorted(by: byX)
        return Array(zip(list, columns(area, list.count, gap: gap)))
    }

    // overlapOffset shifts a frame down and right while another window's top-left corner sits at its own, up to
    // maxCascade steps of size points, never past the area's far edges. Windows are matched by top-left corner.
    public static func overlapOffset(
        _ frame: Frame, others: [Frame], area: Frame, size: Double, maxCascade: Int, tolerance: Double = 4
    ) -> Frame {
        guard size > 0 else { return frame }
        var f = frame
        for _ in 0..<max(0, min(5, maxCascade)) {
            let hit = others.contains { abs($0.x - f.x) < tolerance && abs($0.y - f.y) < tolerance }
            guard hit else { break }
            let dx = f.x + f.w + size <= area.x + area.w ? size : 0
            let dy = f.y + f.h + size <= area.y + area.h ? size : 0
            guard dx != 0 || dy != 0 else { break }
            f.x += dx
            f.y += dy
        }
        return f
    }
}
