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

// Tile holds the organize frame math: columns, rows, a grid, a cascade and a mirror. Every function
// is pure.
public enum Tile {
    // names lists the organize actions in menu order.
    public static let names = [
        "tile-columns", "tile-rows", "tile-all", "tile-active-app", "cascade-all", "cascade-active-app",
        "cycle-stacked-windows", "cycle-stacked-windows-backward", "reverse-all",
    ]

    // cascadeStep is how far in points each cascaded window sits from the last.
    public static let cascadeStep = 30.0

    // handles reports whether name is an organize action.
    public static func handles(_ name: String) -> Bool {
        names.contains(name)
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
        -> [(TileWindow, Frame)] {
        let list = Array(front.prefix(max(n, 0))).sorted(by: byX)
        return Array(zip(list, columns(area, list.count, gap: gap)))
    }
}
