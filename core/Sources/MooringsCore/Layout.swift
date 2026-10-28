import Foundation

// Widths holds the left and right strip widths as percentages of the ultrawide's width.
public struct Widths: Equatable, Sendable, Codable {
    // left is the left strip width.
    public var left: Double
    // right is the right strip width.
    public var right: Double

    // init builds a width pair.
    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }
}

// Heights holds each side's top row height as a percentage of the strip's height.
public struct Heights: Equatable, Sendable, Codable {
    // left is the left strip's top row height.
    public var left: Double
    // right is the right strip's top row height.
    public var right: Double

    // init builds a height pair.
    public init(left: Double, right: Double) {
        self.left = left
        self.right = right
    }

    // subscript reads or writes one side's top row height.
    public subscript(side: Side) -> Double {
        get { side == .left ? left : right }
        set {
            if side == .left {
                left = newValue
            } else {
                right = newValue
            }
        }
    }
}

// PartialHeights is a saved or configured height pair where either side may be missing or junk.
public struct PartialHeights: Equatable, Sendable {
    // left is the left top row height, nil when missing.
    public var left: Double?
    // right is the right top row height, nil when missing.
    public var right: Double?

    // init builds a partial pair.
    public init(left: Double? = nil, right: Double? = nil) {
        self.left = left
        self.right = right
    }

    // subscript reads one side.
    public subscript(side: Side) -> Double? {
        side == .left ? left : right
    }
}

// Layout holds the strip width and row height rules: which values are usable, which wins, and
// how the steppers move them.
public enum Layout {
    // minChannelPct is the narrowest channel a width pair may leave.
    public static let minChannelPct = 10.0
    // minRowPct is the shortest share of a strip's height either row may take.
    public static let minRowPct = 10.0
    // minAspect is the width-to-height ratio a screen needs to count as ultrawide.
    public static let minAspect = 2.2
    // defaultWidths applies when neither a saved choice nor the config leaves a channel.
    public static let defaultWidths = Widths(left: 10, right: 45)
    // defaultTop splits a strip evenly.
    public static let defaultTop = 50.0
    // widthStep is how many percentage points a width stepper moves.
    public static let widthStep = 1.0
    // heightStep is how many percentage points a height stepper moves.
    public static let heightStep = 5.0

    // presets are the built-in width pairs offered in the menu, far enough apart to look different.
    public static let presets: [Widths] = [
        Widths(left: 10, right: 30),
        Widths(left: 15, right: 40),
        Widths(left: 20, right: 45),
    ]

    // heightPresets are the top row heights offered for each side in the menu.
    public static let heightPresets: [Double] = [10, 25, 33, 50, 67, 75, 90]

    // validSplit reports whether a width pair leaves a usable channel.
    public static func validSplit(_ w: Widths?) -> Bool {
        guard let w else { return false }
        return w.left > 0 && w.right > 0 && w.left + w.right <= 100 - minChannelPct
    }

    // widths returns the width pair in effect and a warning when it fell back to the defaults. A
    // saved choice wins over the config.
    public static func widths(saved: Widths?, config: Widths?) -> (Widths, warning: String?) {
        if validSplit(saved), let saved {
            return (saved, nil)
        }
        if validSplit(config), let config {
            return (config, nil)
        }
        return (defaultWidths, "leftPct and rightPct leave no channel: using 10 and 45")
    }

    // held reports whether an app that will not shrink below minPoints holds a strip of pct on a
    // screen screenWidth points wide.
    public static func held(minPoints: Double, screenWidth: Double, pct: Double) -> Bool {
        minPoints > floor(screenWidth * pct / 100)
    }

    // widthRange returns the whole percentages side may take with the other side as in w: from the
    // smallest that holds an app minPoints wide, at least 1, to the most that leaves the channel at
    // minChannelPct. The floor rises to the ceiling when the app cannot fit.
    public static func widthRange(_ w: Widths, _ side: Side, minPoints: Double = 0, screenWidth: Double? = nil)
        -> ClosedRange<Double> {
        let other = side == .left ? w.right : w.left
        let hi = max(1, floor(100 - minChannelPct - other))
        var lo = 1.0
        if let screenWidth, screenWidth > 0, minPoints > 0 {
            lo = max(lo, ceil(minPoints * 100 / screenWidth))
        }
        return min(lo, hi)...hi
    }

    // clamped returns w with side set to pct, rounded to a whole percent and kept inside widthRange.
    public static func clamped(_ w: Widths, _ side: Side, _ pct: Double, minPoints: Double = 0,
                               screenWidth: Double? = nil) -> Widths {
        let r = widthRange(w, side, minPoints: minPoints, screenWidth: screenWidth)
        let v = min(max(pct.rounded(), r.lowerBound), r.upperBound)
        var out = w
        if side == .left {
            out.left = v
        } else {
            out.right = v
        }
        return out
    }

    // clampedTop returns pct rounded to a whole percent and kept between minRowPct and 100 - minRowPct.
    public static func clampedTop(_ pct: Double) -> Double {
        min(max(pct.rounded(), minRowPct), 100 - minRowPct)
    }

    // points returns how many points pct of a screen screenWidth points wide covers, rounded down.
    public static func points(_ pct: Double, screenWidth: Double) -> Double {
        floor(screenWidth * pct / 100)
    }

    // stepped returns the widths after moving side by delta, and whether they still leave a usable
    // channel and do not narrow a side an app holds wider. minPoints is the learned minimum width
    // of the side's pin, zero when none.
    public static func stepped(_ w: Widths, _ side: Side, _ delta: Double, minPoints: Double = 0, screenWidth: Double? = nil)
        -> (Widths, ok: Bool) {
        var out = w
        if side == .left {
            out.left += delta
        } else {
            out.right += delta
        }
        let pct = side == .left ? out.left : out.right
        let narrowHeld = delta < 0 && screenWidth.map { held(minPoints: minPoints, screenWidth: $0, pct: pct) } == true
        return (out, validSplit(out) && !narrowHeld)
    }

    // validTop reports whether pct leaves both rows of a strip at least minRowPct tall.
    public static func validTop(_ pct: Double?) -> Bool {
        guard let pct else { return false }
        return pct >= minRowPct && pct <= 100 - minRowPct
    }

    // heights returns the top row heights in effect, side by side, with a warning for each
    // configured side that is set but unusable. A saved choice wins over the config.
    public static func heights(saved: PartialHeights, config: PartialHeights, configSet: Set<Side> = [])
        -> (Heights, warnings: [String]) {
        var out = Heights(left: defaultTop, right: defaultTop)
        var warnings: [String] = []
        for side in [Side.left, .right] {
            if validTop(saved[side]), let pct = saved[side] {
                out[side] = pct
            } else if validTop(config[side]), let pct = config[side] {
                out[side] = pct
            } else if config[side] != nil || configSet.contains(side) {
                warnings.append("\(side.rawValue)TopPct must be a number from 10 to 90: using 50")
            }
        }
        return (out, warnings)
    }

    // topStepped returns side's top row height after moving it by delta, and whether both rows stay
    // at least minRowPct tall.
    public static func topStepped(_ h: Heights, _ side: Side, _ delta: Double) -> (Double, ok: Bool) {
        let pct = h[side] + delta
        return (pct, validTop(pct))
    }

    // ultrawide returns the index of the widest screen at or above minAspect, or nil. Each frame is
    // a screen's full frame.
    public static func ultrawide(_ screens: [Frame], minAspect: Double = minAspect) -> Int? {
        var best: Int?
        var bestRatio = 0.0
        for (index, f) in screens.enumerated() {
            let ratio = f.h > 0 ? f.w / f.h : 0
            if ratio >= minAspect && ratio > bestRatio {
                best = index
                bestRatio = ratio
            }
        }
        return best
    }
}
