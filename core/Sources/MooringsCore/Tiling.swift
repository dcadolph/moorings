import Foundation

// TileMode is a layout the tiler keeps the free windows of each display in as they come and go.
public enum TileMode: String, CaseIterable, Codable, Sendable {
    case off, tall, wide, columns, rows, bsp
}

// TileDirection is a way to look for a neighboring window.
public enum TileDirection: String, CaseIterable, Sendable {
    case left, right, up, down
}

// TilingChoices holds the tiling mode and the main pane's share of the area.
public struct TilingChoices: Equatable, Sendable, Codable {
    // mode is the layout, off by default.
    public var mode: TileMode = .off
    // ratio is the main pane's share of the area in tall and wide, from Tiling.ratios.
    public var ratio = 0.5

    // CodingKeys names the encoded fields.
    enum CodingKeys: String, CodingKey {
        case mode, ratio
    }

    // init builds the default tiling choices: off, with an even split.
    public init(mode: TileMode = .off, ratio: Double = 0.5) {
        self.mode = mode
        self.ratio = Tiling.clamp(ratio)
    }

    // init decodes tiling choices, keeping the default for any field missing or unreadable and
    // clamping the ratio.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? c.decodeIfPresent(TileMode.self, forKey: .mode)) ?? .off
        ratio = Tiling.clamp((try? c.decodeIfPresent(Double.self, forKey: .ratio)) ?? 0.5)
    }
}

// Tiling holds the auto tiling math: the frames of each mode, the neighbor in a direction, and the
// order windows keep as others come and go. Every function is pure.
public enum Tiling {
    // ratios is the range the main pane's share may take.
    public static let ratios = 0.2...0.8
    // ratioStep is how much grow-main and shrink-main change the share.
    public static let ratioStep = 0.05
    // modePrefix starts the action name of each mode.
    public static let modePrefix = "tiling-"
    // cycleName is the action that steps to the next mode.
    public static let cycleName = "cycle-tiling"

    // modeNames lists the mode actions in menu order.
    public static let modeNames = TileMode.allCases.map { modePrefix + $0.rawValue }
    // focusNames lists the actions that focus the neighbor in a direction.
    public static let focusNames = TileDirection.allCases.map { "focus-\($0.rawValue)" }
    // swapNames lists the actions that swap the focused window with its neighbor in a direction.
    public static let swapNames = TileDirection.allCases.map { "swap-\($0.rawValue)" }
    // names lists every tiling action in menu order.
    public static let names = modeNames + [cycleName, "grow-main", "shrink-main"] + focusNames + swapNames

    // handles reports whether name is a tiling action.
    public static func handles(_ name: String) -> Bool {
        names.contains(name)
    }

    // mode returns the mode a mode action sets, nil for any other name.
    public static func mode(_ name: String) -> TileMode? {
        name.hasPrefix(modePrefix) ? TileMode(rawValue: String(name.dropFirst(modePrefix.count))) : nil
    }

    // direction returns the direction of a focus or swap action, nil for any other name.
    public static func direction(_ name: String) -> TileDirection? {
        guard let dash = name.firstIndex(of: "-"), focusNames.contains(name) || swapNames.contains(name) else {
            return nil
        }
        return TileDirection(rawValue: String(name[name.index(after: dash)...]))
    }

    // next returns the mode after mode for cycle-tiling, skipping off.
    public static func next(_ mode: TileMode) -> TileMode {
        let on = TileMode.allCases.filter { $0 != .off }
        guard let i = on.firstIndex(of: mode) else { return on[0] }
        return on[(i + 1) % on.count]
    }

    // clamp returns ratio held inside ratios.
    public static func clamp(_ ratio: Double) -> Double {
        min(ratios.upperBound, max(ratios.lowerBound, ratio))
    }

    // resized returns the main pane's share after one grow-main or shrink-main.
    public static func resized(_ ratio: Double, grow: Bool) -> Double {
        clamp(((ratio + (grow ? ratioStep : -ratioStep)) * 100).rounded() / 100)
    }

    // layout returns the frames of n windows in mode inside area, main window first, with gap points
    // around and between them. Tall puts the main window on the left at ratio of the width and
    // stacks the rest on the right. Wide puts it on top and lines the rest up below. BSP gives each
    // window half of what is left, split across the longer side.
    public static func layout(_ mode: TileMode, _ area: Frame, _ n: Int, ratio: Double, gap: Double = 0) -> [Frame] {
        guard n > 0, mode != .off else { return [] }
        let inner = inset(area, gap)
        switch mode {
        case .off:
            return []
        case .columns:
            return Tile.columns(area, n, gap: gap)
        case .rows:
            return Tile.rows(area, n, gap: gap)
        case .tall, .wide:
            if n == 1 {
                return [inner]
            }
            let (main, rest) = split(inner, ratio, across: mode == .tall, gap: gap)
            let others =
                mode == .tall
                ? Tile.rows(inset(rest, -gap), n - 1, gap: gap)
                : Tile.columns(inset(rest, -gap), n - 1, gap: gap)
            return [main] + others
        case .bsp:
            var out: [Frame] = []
            var left = inner
            for _ in 0..<(n - 1) {
                let (part, rest) = split(left, 0.5, across: left.w >= left.h, gap: gap)
                out.append(part)
                left = rest
            }
            return out + [left]
        }
    }

    // split cuts f in two with gap points between, the first part taking share of the width when
    // across is true and of the height otherwise.
    static func split(_ f: Frame, _ share: Double, across: Bool, gap: Double) -> (Frame, Frame) {
        if across {
            let w = (max(0, f.w - gap) * share).rounded()
            return (Frame(x: f.x, y: f.y, w: w, h: f.h), Frame(x: f.x + w + gap, y: f.y, w: f.w - w - gap, h: f.h))
        }
        let h = (max(0, f.h - gap) * share).rounded()
        return (Frame(x: f.x, y: f.y, w: f.w, h: h), Frame(x: f.x, y: f.y + h + gap, w: f.w, h: f.h - h - gap))
    }

    // inset returns f shrunk by d points on every side, or grown when d is negative.
    static func inset(_ f: Frame, _ d: Double) -> Frame {
        Frame(x: f.x + d, y: f.y + d, w: f.w - 2 * d, h: f.h - 2 * d)
    }

    // toward returns the index of the frame nearest frames[i] in direction dir, nil when none lies
    // that way. A frame counts when its center is past frames[i]'s center that way. Frames that
    // overlap frames[i] across the direction win over those that do not, then the nearest center
    // along the direction, with distance across it counted double.
    public static func toward(_ dir: TileDirection, from i: Int, frames: [Frame]) -> Int? {
        guard frames.indices.contains(i) else { return nil }
        let me = frames[i]
        let flat = dir == .left || dir == .right
        let sign = dir == .left || dir == .up ? -1.0 : 1.0
        var best: (k: Int, beside: Bool, score: Double)?
        for (k, f) in frames.enumerated() where k != i {
            let dx = (f.x + f.w / 2) - (me.x + me.w / 2)
            let dy = (f.y + f.h / 2) - (me.y + me.h / 2)
            let along = sign * (flat ? dx : dy)
            guard along > 0 else { continue }
            let beside = flat ? f.y < me.y + me.h && f.y + f.h > me.y : f.x < me.x + me.w && f.x + f.w > me.x
            let score = along + 2 * abs(flat ? dy : dx)
            if let b = best, b.beside && !beside || b.beside == beside && b.score <= score {
                continue
            }
            best = (k, beside, score)
        }
        return best?.k
    }

    // order returns the tiling order after the windows on screen became current, front-most first:
    // windows already in previous keep their places, and new ones join at the end, front-most first.
    public static func order(_ previous: [WindowID], _ current: [WindowID]) -> [WindowID] {
        let now = Set(current)
        let kept = previous.filter { now.contains($0) }
        let had = Set(kept)
        return kept + current.filter { !had.contains($0) }
    }

    // swapped returns order with a and b trading places, unchanged when either is missing.
    public static func swapped(_ order: [WindowID], _ a: WindowID, _ b: WindowID) -> [WindowID] {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return order }
        var out = order
        out.swapAt(i, j)
        return out
    }
}
