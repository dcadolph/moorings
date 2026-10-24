import Foundation

// Frame is a window or screen rectangle in global top-left coordinates, in points.
public struct Frame: Equatable, Sendable, CustomStringConvertible {
    // x is the left edge.
    public var x: Double
    // y is the top edge.
    public var y: Double
    // w is the width.
    public var w: Double
    // h is the height.
    public var h: Double

    // init builds a frame from its edges and size.
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    // description formats the frame for test output and logs.
    public var description: String { "{\(x.formatted()),\(y.formatted()),\(w.formatted()),\(h.formatted())}" }
}

// Side names a screen edge that holds a strip.
public enum Side: String, Sendable {
    case left, right
}

// Row names the half of a strip a pin sits in.
public enum Row: String, Sendable {
    case top, bottom
}

// Regions splits a screen into the left strip, the channel and the right strip.
public struct Regions: Equatable, Sendable {
    // left is the left strip.
    public var left: Frame
    // channel is the space between the strips.
    public var channel: Frame
    // right is the right strip.
    public var right: Frame
}

// Cell describes a grid position as columns c0 to c1 of nc and rows r0 to r1 of nr. orient swaps
// the axes on a portrait area, so a first third is the left column on a wide area and the top row
// on a tall one.
public struct Cell: Equatable, Sendable {
    // c0 is the first column.
    public var c0: Int
    // c1 is the column after the last.
    public var c1: Int
    // nc is the column count.
    public var nc: Int
    // r0 is the first row.
    public var r0: Int
    // r1 is the row after the last.
    public var r1: Int
    // nr is the row count.
    public var nr: Int
    // orient reports whether the axes swap on a portrait area.
    public var orient: Bool

    // init builds a cell.
    public init(_ c0: Int, _ c1: Int, _ nc: Int, _ r0: Int, _ r1: Int, _ nr: Int, orient: Bool = false) {
        self.c0 = c0
        self.c1 = c1
        self.nc = nc
        self.r0 = r0
        self.r1 = r1
        self.nr = nr
        self.orient = orient
    }
}

// Placement is a named grid position: one cell, or a corner third with its own landscape and
// portrait cells.
public enum Placement: Equatable, Sendable {
    case cell(Cell)
    case corner(landscape: Cell, portrait: Cell)
}

// Step is one press of a cycling action: a named position, or a cell that ignores orientation.
public enum Step: Equatable, Sendable {
    case named(String)
    case cell(Cell)
}

// CustomSpec is a custom size: x, y, w and h as shares of the area, and an optional width and
// height in points that center a window of that size in the share, shrunk to fit when larger.
public struct CustomSpec: Equatable, Sendable {
    // x is the share of the width before the left edge.
    public var x: Double
    // y is the share of the height above the top edge.
    public var y: Double
    // w is the share of the width.
    public var w: Double
    // h is the share of the height.
    public var h: Double
    // width is an optional width in points.
    public var width: Double?
    // height is an optional height in points.
    public var height: Double?

    // init builds a spec, defaulting to the whole area.
    public init(x: Double = 0, y: Double = 0, w: Double = 1, h: Double = 1, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.width = width
        self.height = height
    }
}

// Geometry holds the frame math moorings uses. Every function is pure: it takes frames and numbers
// and returns new frames.
public enum Geometry {
    // edge returns the frame an edge of pct width occupies on f.
    public static func edge(_ f: Frame, _ side: Side, _ pct: Double) -> Frame {
        let w = floor(f.w * pct / 100)
        if side == .right {
            return Frame(x: f.x + f.w - w, y: f.y, w: w, h: f.h)
        }
        return Frame(x: f.x, y: f.y, w: w, h: f.h)
    }

    // slot returns the frame a pin in row of side occupies on f at pct width. A nil row fills the
    // strip's full height. The top row is topPct percent of the height, half when topPct is nil,
    // and the bottom row takes the rest.
    public static func slot(_ f: Frame, _ side: Side, _ row: Row?, _ pct: Double, topPct: Double? = nil) -> Frame {
        var r = edge(f, side, pct)
        let top = floor(f.h * (topPct ?? 50) / 100)
        switch row {
        case .top:
            r.h = top
        case .bottom:
            r.y = f.y + top
            r.h = f.h - top
        case nil:
            break
        }
        return r
    }

    // regions splits f into the left edge, the channel and the right edge.
    public static func regions(_ f: Frame, _ leftPct: Double, _ rightPct: Double) -> Regions {
        let left = edge(f, .left, leftPct)
        let right = edge(f, .right, rightPct)
        let channel = Frame(x: left.x + left.w, y: f.y, w: right.x - left.x - left.w, h: f.h)
        return Regions(left: left, channel: channel, right: right)
    }

    // lift returns the frame a lifted pin on side takes on f: its own strip and the channel at full
    // height, stopping at the other strip.
    public static func lift(_ f: Frame, _ side: Side, _ leftPct: Double, _ rightPct: Double) -> Frame {
        let r = regions(f, leftPct, rightPct)
        if side == .right {
            let x = r.left.x + r.left.w
            return Frame(x: x, y: f.y, w: f.x + f.w - x, h: f.h)
        }
        return Frame(x: f.x, y: f.y, w: r.right.x - f.x, h: f.h)
    }

    // clamp fits f inside ch, shrinking it only when it is larger than ch.
    public static func clamp(_ f: Frame, _ ch: Frame) -> Frame {
        let w = min(f.w, ch.w)
        let h = min(f.h, ch.h)
        return Frame(
            x: max(ch.x, min(f.x, ch.x + ch.w - w)),
            y: max(ch.y, min(f.y, ch.y + ch.h - h)),
            w: w,
            h: h
        )
    }

    // cornerThird returns the corner third that is two thirds wide and half tall on a wide area, and
    // half wide and two thirds tall on a tall one.
    private static func cornerThird(right: Bool, bottom: Bool) -> Placement {
        let c = right ? (1, 3) : (0, 2)
        let r = bottom ? (1, 2) : (0, 1)
        let pc = right ? (1, 2) : (0, 1)
        let pr = bottom ? (1, 3) : (0, 2)
        return .corner(
            landscape: Cell(c.0, c.1, 3, r.0, r.1, 2),
            portrait: Cell(pc.0, pc.1, 2, pr.0, pr.1, 3)
        )
    }

    // grid returns a cell for every square of an nc by nr grid, named by rowNames and colNames
    // joined with a hyphen and the suffix, with the names in reading order.
    private static func grid(_ nc: Int, _ nr: Int, _ colNames: [String], _ rowNames: [String], _ suffix: String)
        -> [(String, Placement)] {
        var out: [(String, Placement)] = []
        for (r, rowName) in rowNames.enumerated() {
            for (c, colName) in colNames.enumerated() {
                out.append(("\(rowName)-\(colName)-\(suffix)", .cell(Cell(c, c + 1, nc, r, r + 1, nr))))
            }
        }
        return out
    }

    // sixths, ninths and eighths are the grid families with their names in reading order.
    private static let sixths = grid(3, 2, ["left", "center", "right"], ["top", "bottom"], "sixth")
    private static let ninths = grid(3, 3, ["left", "center", "right"], ["top", "middle", "bottom"], "ninth")
    private static let eighths = grid(4, 2, ["left", "center-left", "center-right", "right"], ["top", "bottom"], "eighth")

    // verticalStrips returns the full-height columns of an n-column grid, named by ordinals.
    private static func verticalStrips(_ n: Int, _ ordinals: [String], _ suffix: String) -> [(String, Placement)] {
        ordinals.enumerated().map { ("\($0.element)-vertical-\(suffix)", .cell(Cell($0.offset, $0.offset + 1, n, 0, 1, 1))) }
    }

    // verticalSixths and verticalEighths are the full-height column families on a landscape area.
    private static let verticalSixths = verticalStrips(
        6, ["first", "second", "third", "fourth", "fifth", "last"], "sixth")
    private static let verticalEighths = verticalStrips(
        8, ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "last"], "eighth")

    // twelfths and sixteenths are the 4 by 3 and 4 by 4 grid families in reading order.
    private static let twelfths = grid(
        4, 3, ["left", "center-left", "center-right", "right"], ["top", "middle", "bottom"], "twelfth")
    private static let sixteenths = grid(
        4, 4, ["left", "center-left", "center-right", "right"],
        ["top", "upper-middle", "lower-middle", "bottom"], "sixteenth")

    // verticalThirds are the row-based thirds and two thirds, named after Rectangle's.
    private static let verticalThirds: [(String, Placement)] = [
        ("top-vertical-third", .cell(Cell(0, 1, 1, 0, 1, 3))),
        ("middle-vertical-third", .cell(Cell(0, 1, 1, 1, 2, 3))),
        ("bottom-vertical-third", .cell(Cell(0, 1, 1, 2, 3, 3))),
        ("top-vertical-two-thirds", .cell(Cell(0, 1, 1, 0, 2, 3))),
        ("bottom-vertical-two-thirds", .cell(Cell(0, 1, 1, 1, 3, 3))),
    ]

    // grids lists the grid position names by family, in reading order.
    public static let grids: [String: [String]] = [
        "sixths": sixths.map(\.0),
        "ninths": ninths.map(\.0),
        "eighths": eighths.map(\.0),
        "verticalSixths": verticalSixths.map(\.0),
        "verticalEighths": verticalEighths.map(\.0),
        "twelfths": twelfths.map(\.0),
        "sixteenths": sixteenths.map(\.0),
        "verticalThirds": verticalThirds.map(\.0),
        "cornerThirds": ["top-left-third", "top-right-third", "bottom-left-third", "bottom-right-third"],
    ]

    // cells maps each grid action name to its placement. The names match Rectangle's.
    public static let cells: [String: Placement] = {
        var cells: [String: Placement] = [
            "left-half": .cell(Cell(0, 1, 2, 0, 1, 1)),
            "right-half": .cell(Cell(1, 2, 2, 0, 1, 1)),
            "center-half": .cell(Cell(1, 3, 4, 0, 1, 1)),
            "top-half": .cell(Cell(0, 1, 1, 0, 1, 2)),
            "bottom-half": .cell(Cell(0, 1, 1, 1, 2, 2)),
            "top-left": .cell(Cell(0, 1, 2, 0, 1, 2)),
            "top-right": .cell(Cell(1, 2, 2, 0, 1, 2)),
            "bottom-left": .cell(Cell(0, 1, 2, 1, 2, 2)),
            "bottom-right": .cell(Cell(1, 2, 2, 1, 2, 2)),
            "first-third": .cell(Cell(0, 1, 3, 0, 1, 1, orient: true)),
            "center-third": .cell(Cell(1, 2, 3, 0, 1, 1, orient: true)),
            "last-third": .cell(Cell(2, 3, 3, 0, 1, 1, orient: true)),
            "first-two-thirds": .cell(Cell(0, 2, 3, 0, 1, 1, orient: true)),
            "center-two-thirds": .cell(Cell(1, 5, 6, 0, 1, 1, orient: true)),
            "last-two-thirds": .cell(Cell(1, 3, 3, 0, 1, 1, orient: true)),
            "first-fourth": .cell(Cell(0, 1, 4, 0, 1, 1, orient: true)),
            "second-fourth": .cell(Cell(1, 2, 4, 0, 1, 1, orient: true)),
            "third-fourth": .cell(Cell(2, 3, 4, 0, 1, 1, orient: true)),
            "last-fourth": .cell(Cell(3, 4, 4, 0, 1, 1, orient: true)),
            "first-three-fourths": .cell(Cell(0, 3, 4, 0, 1, 1, orient: true)),
            "center-three-fourths": .cell(Cell(1, 7, 8, 0, 1, 1, orient: true)),
            "last-three-fourths": .cell(Cell(1, 4, 4, 0, 1, 1, orient: true)),
            "top-left-third": cornerThird(right: false, bottom: false),
            "top-right-third": cornerThird(right: true, bottom: false),
            "bottom-left-third": cornerThird(right: false, bottom: true),
            "bottom-right-third": cornerThird(right: true, bottom: true),
        ]
        for (name, placement) in sixths + ninths + eighths + verticalSixths + verticalEighths + twelfths
            + sixteenths + verticalThirds {
            cells[name] = placement
        }
        return cells
    }()

    // span returns the start and length of parts i0 to i1 of n across length at origin, with the
    // outer gap at the area's edges and half the gap between parts.
    private static func span(_ origin: Double, _ length: Double, _ i0: Int, _ i1: Int, _ n: Int, _ gap: Double)
        -> (Double, Double) {
        var a = origin + floor(length * Double(i0) / Double(n))
        var b = origin + floor(length * Double(i1) / Double(n))
        let half = floor(gap / 2)
        a += i0 == 0 ? gap : gap - half
        b -= i1 == n ? gap : half
        return (a, b - a)
    }

    // inset shrinks f by gap on every side.
    private static func inset(_ f: Frame, _ gap: Double) -> Frame {
        Frame(x: f.x + gap, y: f.y + gap, w: f.w - 2 * gap, h: f.h - 2 * gap)
    }

    // fromCell returns the frame of a cell inside area, honoring orientation and gap.
    private static func fromCell(_ cell: Cell, _ area: Frame, _ gap: Double) -> Frame {
        var c = cell
        if c.orient && area.h > area.w {
            c = Cell(c.r0, c.r1, c.nr, c.c0, c.c1, c.nc)
        }
        let (x, w) = span(area.x, area.w, c.c0, c.c1, c.nc, gap)
        let (y, h) = span(area.y, area.h, c.r0, c.r1, c.nr, gap)
        return Frame(x: x, y: y, w: w, h: h)
    }

    // fromPlacement returns the frame of a placement inside area, picking a corner third's cell by
    // the area's orientation.
    private static func fromPlacement(_ placement: Placement, _ area: Frame, _ gap: Double) -> Frame {
        switch placement {
        case let .cell(cell):
            return fromCell(cell, area, gap)
        case let .corner(landscape, portrait):
            return fromCell(area.h > area.w ? portrait : landscape, area, gap)
        }
    }

    // part returns the frame of columns c0 to c1 of nc and rows r0 to r1 of nr inside area, with gap
    // points around and between parts.
    public static func part(_ area: Frame, _ c0: Int, _ c1: Int, _ nc: Int, _ r0: Int, _ r1: Int, _ nr: Int, gap: Double = 0)
        -> Frame {
        fromCell(Cell(c0, c1, nc, r0, r1, nr), area, gap)
    }

    // round returns n rounded to the nearest whole point, with halves rounding up.
    private static func round(_ n: Double) -> Double {
        floor(n + 0.5)
    }

    // center returns cur centered in area, filling an axis it is too large for.
    private static func center(_ area: Frame, _ cur: Frame) -> Frame {
        var f = cur
        if f.w > area.w {
            f.x = area.x
            f.w = area.w
        } else {
            f.x = area.x + round((area.w - f.w) / 2)
        }
        if f.h > area.h {
            f.y = area.y
            f.h = area.h
        } else {
            f.y = area.y + round((area.h - f.h) / 2)
        }
        return f
    }

    // Direction names the edge a move action pushes a window against.
    private enum Direction {
        case left, right, up, down
    }

    // slide returns cur pushed against one edge of area, centered on the other axis.
    private static func slide(_ area: Frame, _ cur: Frame, _ dir: Direction) -> Frame {
        var f = center(area, cur)
        switch dir {
        case .left: f.x = area.x
        case .right: f.x = area.x + area.w - f.w
        case .up: f.y = area.y
        case .down: f.y = area.y + area.h - f.h
        }
        return f
    }

    // almost is the share of the area almost-maximize fills on each axis.
    private static let almost = 0.9

    // relative maps each action that depends on the window's own frame to the function that
    // computes it from the work area, the current frame and the gap.
    private static let relative: [String: @Sendable (Frame, Frame, Double) -> Frame] = [
        "maximize": { area, _, gap in inset(area, gap) },
        "almost-maximize": { area, _, _ in
            let w = round(area.w * almost)
            let h = round(area.h * almost)
            return Frame(x: area.x + round((area.w - w) / 2), y: area.y + round((area.h - h) / 2), w: w, h: h)
        },
        "maximize-height": { area, cur, gap in Frame(x: cur.x, y: area.y + gap, w: cur.w, h: area.h - 2 * gap) },
        "center": { area, cur, gap in center(inset(area, gap), cur) },
        "center-prominently": { area, cur, gap in
            let a = inset(area, gap)
            var f = center(a, cur)
            f.y -= round((a.h - f.h) / 4)
            return f
        },
        "move-left": { area, cur, gap in slide(inset(area, gap), cur, .left) },
        "move-right": { area, cur, gap in slide(inset(area, gap), cur, .right) },
        "move-up": { area, cur, gap in slide(inset(area, gap), cur, .up) },
        "move-down": { area, cur, gap in slide(inset(area, gap), cur, .down) },
    ]

    // position returns the frame action name gives a window at cur inside area, leaving gap points
    // around and between windows. It returns nil for a name it does not know.
    public static func position(_ name: String, _ area: Frame, _ cur: Frame? = nil, gap: Double = 0) -> Frame? {
        if let placement = cells[name] {
            return fromPlacement(placement, area, gap)
        }
        if let fn = relative[name] {
            return fn(area, cur ?? area, gap)
        }
        return nil
    }

    // cycles maps each action that changes on a repeat press to the positions it steps through. A
    // cell step ignores orientation, so a half cycles its width on a tall area as well.
    public static let cycles: [String: [Step]] = [
        "left-half": [.named("left-half"), .cell(Cell(0, 2, 3, 0, 1, 1)), .cell(Cell(0, 1, 3, 0, 1, 1))],
        "right-half": [.named("right-half"), .cell(Cell(1, 3, 3, 0, 1, 1)), .cell(Cell(2, 3, 3, 0, 1, 1))],
        "first-third": [.named("first-third"), .named("center-third"), .named("last-third")],
        "last-third": [.named("last-third"), .named("center-third"), .named("first-third")],
    ]

    // cycle returns the frame of press i, counted from 1, of action name, wrapping after the last
    // step. A name without a cycle returns its plain position.
    public static func cycle(_ name: String, _ i: Int, _ area: Frame, _ cur: Frame? = nil, gap: Double = 0) -> Frame? {
        guard let steps = cycles[name] else {
            return position(name, area, cur, gap: gap)
        }
        let index = ((i - 1) % steps.count + steps.count) % steps.count
        switch steps[index] {
        case let .named(step):
            return position(step, area, cur, gap: gap)
        case let .cell(cell):
            return fromCell(cell, area, gap)
        }
    }

    // minShare is the smallest share of the area resize will shrink an axis to.
    private static let minShare = 0.25

    // touch is how many points from an area edge still count as touching it.
    private static let touch = 2.0

    // grow moves the free edges of the span lo to lo+len by d within alo to alo+alen. An edge
    // touching the area stays put, like a curtain. When shrinking a span that touches both edges,
    // both edges move in.
    private static func grow(_ lo: Double, _ len: Double, _ alo: Double, _ alen: Double, _ d: Double) -> (Double, Double) {
        let hi = lo + len
        let ahi = alo + alen
        var atLo = lo <= alo + touch
        var atHi = hi >= ahi - touch
        if d < 0 && atLo && atHi {
            atLo = false
            atHi = false
        }
        let nlo = atLo ? lo : max(alo, lo - d)
        let nhi = atHi ? hi : min(ahi, hi + d)
        if d < 0 && nhi - nlo < alen * minShare {
            return (lo, len)
        }
        return (nlo, nhi - nlo)
    }

    // resize grows cur by d points on each free edge inside area, or shrinks it when d is negative.
    // cur is first clamped into the area.
    public static func resize(_ area: Frame, _ cur: Frame, _ d: Double, gap: Double = 0) -> Frame {
        let a = inset(area, gap)
        let f = clamp(cur, a)
        let (x, w) = grow(f.x, f.w, a.x, a.w, d)
        let (y, h) = grow(f.y, f.h, a.y, a.h, d)
        return Frame(x: x, y: y, w: w, h: h)
    }

    // transfer maps cur from one area to another, keeping its relative position and size, so a left
    // half stays a left half on the next display.
    public static func transfer(_ cur: Frame, from: Frame, to: Frame) -> Frame {
        let sx = to.w / from.w
        let sy = to.h / from.h
        let f = Frame(
            x: to.x + round((cur.x - from.x) * sx),
            y: to.y + round((cur.y - from.y) * sy),
            w: round(cur.w * sx),
            h: round(cur.h * sy)
        )
        return clamp(f, to)
    }

    // fspan returns the start and length of the share f0 to f1 of length at origin, with the outer
    // gap at the area's edges and half the gap between neighbors. It floors like span, with a little
    // slack so a share such as 2/3 does not lose a point to float error.
    private static func fspan(_ origin: Double, _ length: Double, _ f0: Double, _ f1: Double, _ gap: Double)
        -> (Double, Double) {
        var a = origin + floor(length * f0 + 1e-9)
        var b = origin + floor(length * f1 + 1e-9)
        let half = floor(gap / 2)
        a += f0 < 1e-9 ? gap : gap - half
        b -= f1 > 1 - 1e-9 ? gap : half
        return (a, b - a)
    }

    // custom returns the frame of a custom size inside area.
    public static func custom(_ area: Frame, _ spec: CustomSpec, gap: Double = 0) -> Frame {
        var (x, w) = fspan(area.x, area.w, spec.x, spec.x + spec.w, gap)
        var (y, h) = fspan(area.y, area.h, spec.y, spec.y + spec.h, gap)
        if let width = spec.width, width < w {
            x += round((w - width) / 2)
            w = width
        }
        if let height = spec.height, height < h {
            y += round((h - height) / 2)
            h = height
        }
        return Frame(x: x, y: y, w: w, h: h)
    }

    // names returns every action position knows, sorted.
    public static func names() -> [String] {
        (Array(cells.keys) + Array(relative.keys)).sorted()
    }
}
