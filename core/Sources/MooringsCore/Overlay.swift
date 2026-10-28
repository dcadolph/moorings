import Foundation

// OverlayTrigger names the key that brings up the overlay while it is held.
public enum OverlayTrigger: String, Codable, CaseIterable, Sendable {
    case none, rightOption, rightCommand, rightControl, fn

    // title is the trigger's name in Settings.
    public var title: String {
        switch self {
        case .none: "None"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        case .fn: "Fn"
        }
    }

    // key is the bit set only while the trigger's own key is down: the right-hand bit of its
    // modifier, or Fn. None has no key.
    public var key: Modifiers {
        switch self {
        case .none: []
        case .rightOption: .rightOption
        case .rightCommand: .rightCommand
        case .rightControl: .rightControl
        case .fn: .function
        }
    }

    // own is the side-free modifier the trigger's key also sets, empty for Fn and None.
    var own: Modifiers {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightControl: .control
        case .none, .fn: []
        }
    }

    // held reports whether m shows the trigger down with no Control, Option or Command besides the
    // trigger's own. Shift may be down, since it grows the grid.
    public func held(_ m: Modifiers) -> Bool {
        guard self != .none, m.isSuperset(of: key) else { return false }
        let others: Modifiers = [.control, .option, .command]
        return m.isDisjoint(with: others.subtracting(own))
    }
}

// OverlayChoices holds the overlay's trigger and its keyboard grid size.
public struct OverlayChoices: Equatable, Sendable, Codable {
    // trigger is the key held to bring up the overlay, none to turn it off.
    public var trigger: OverlayTrigger = .none
    // gridColumns is how many columns the keyboard grid has.
    public var gridColumns: Int = 6
    // gridRows is how many rows the keyboard grid has.
    public var gridRows: Int = 4
    // hoverMove lists the modifiers that, held with no button down, move the window under the pointer
    // as the pointer moves. Empty turns it off.
    public var hoverMove: [Modifier] = []
    // hoverResize lists the modifiers that, held with no button down, resize the window under the
    // pointer from its nearest corner. Empty turns it off.
    public var hoverResize: [Modifier] = []
    // edgeResize lists the modifiers that, held as a drag starts on the edge two windows share,
    // resize both. Empty turns it off.
    public var edgeResize: [Modifier] = []

    // gridRange bounds the grid columns and rows.
    public static let gridRange = 1...12

    // triggerMeetsTiling reports whether the trigger is Right Option, which macOS also reads as the
    // key that tiles a window dragged while it is held.
    public var triggerMeetsTiling: Bool { trigger == .rightOption }

    // hoverMeetsTiling reports whether hover move or resize is Option alone, which macOS also reads
    // as the key that tiles a window dragged while it is held.
    public var hoverMeetsTiling: Bool { hoverMove == [.alt] || hoverResize == [.alt] }

    // gridMeetsSpaces reports whether the trigger is Right Control, whose arrow keys macOS keeps for
    // Mission Control and Spaces, so the keyboard grid never sees them.
    public var gridMeetsSpaces: Bool { trigger == .rightControl }

    // init builds overlay choices at the defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case trigger, gridColumns, gridRows, hoverMove, hoverResize, edgeResize
    }

    // init decodes overlay choices, keeping the default for any field missing or unreadable, clamping
    // the grid size to gridRange and dropping modifier names it does not know.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = Self.gridRange
        trigger = (try? c.decodeIfPresent(OverlayTrigger.self, forKey: .trigger)) ?? .none
        gridColumns = min(
            r.upperBound, max(r.lowerBound, (try? c.decodeIfPresent(Int.self, forKey: .gridColumns)) ?? 6))
        gridRows = min(r.upperBound, max(r.lowerBound, (try? c.decodeIfPresent(Int.self, forKey: .gridRows)) ?? 4))
        hoverMove = Self.mods((try? c.decodeIfPresent([String].self, forKey: .hoverMove)) ?? [])
        hoverResize = Self.mods((try? c.decodeIfPresent([String].self, forKey: .hoverResize)) ?? [])
        edgeResize = Self.mods((try? c.decodeIfPresent([String].self, forKey: .edgeResize)) ?? [])
    }

    // encode writes the overlay choices, modifiers by name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(gridColumns, forKey: .gridColumns)
        try c.encode(gridRows, forKey: .gridRows)
        try c.encode(hoverMove.map(\.rawValue), forKey: .hoverMove)
        try c.encode(hoverResize.map(\.rawValue), forKey: .hoverResize)
        try c.encode(edgeResize.map(\.rawValue), forKey: .edgeResize)
    }

    // mods resolves modifier names in menu order without repeats, dropping unknown names.
    static func mods(_ names: [String]) -> [Modifier] {
        Array(Set(names.compactMap(Modifier.parse))).sorted()
    }
}

// OverlayStep is an arrow direction on the keyboard grid.
public enum OverlayStep: Sendable {
    case left, right, up, down
}

// OverlayGrid is the span of cells picked on the keyboard grid. Like Cell, c1 and r1 are the column
// and row after the last.
public struct OverlayGrid: Equatable, Sendable {
    // cols is the column count.
    public let cols: Int
    // rows is the row count.
    public let rows: Int
    // c0 is the first column of the span.
    public private(set) var c0: Int
    // c1 is the column after the span.
    public private(set) var c1: Int
    // r0 is the first row of the span.
    public private(set) var r0: Int
    // r1 is the row after the span.
    public private(set) var r1: Int

    // init builds a grid of cols by rows with the one cell under p in area picked, or the nearest
    // cell when p is outside it.
    public init(cols: Int, rows: Int, at p: Point, in area: Frame) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
        let fx = area.w > 0 ? (p.x - area.x) / area.w : 0
        let fy = area.h > 0 ? (p.y - area.y) / area.h : 0
        c0 = min(self.cols - 1, max(0, Int(floor(fx * Double(self.cols)))))
        r0 = min(self.rows - 1, max(0, Int(floor(fy * Double(self.rows)))))
        c1 = c0 + 1
        r1 = r0 + 1
    }

    // init builds a grid of cols by rows with the span of cells from the cell under a to the cell
    // under b picked, either way round, each point taken to the nearest cell when it is outside area.
    public init(cols: Int, rows: Int, from a: Point, to b: Point, in area: Frame) {
        let p = OverlayGrid(cols: cols, rows: rows, at: a, in: area)
        let q = OverlayGrid(cols: cols, rows: rows, at: b, in: area)
        self = p
        c0 = min(p.c0, q.c0)
        c1 = max(p.c1, q.c1)
        r0 = min(p.r0, q.r0)
        r1 = max(p.r1, q.r1)
    }

    // moved returns the span shifted one cell toward step, kept inside the grid.
    public func moved(_ step: OverlayStep) -> OverlayGrid {
        var g = self
        switch step {
        case .left where c0 > 0: g.c0 -= 1; g.c1 -= 1
        case .right where c1 < cols: g.c0 += 1; g.c1 += 1
        case .up where r0 > 0: g.r0 -= 1; g.r1 -= 1
        case .down where r1 < rows: g.r0 += 1; g.r1 += 1
        default: break
        }
        return g
    }

    // grown returns the span with its edge toward step pushed out one cell, kept inside the grid.
    public func grown(_ step: OverlayStep) -> OverlayGrid {
        var g = self
        switch step {
        case .left: g.c0 = max(0, c0 - 1)
        case .right: g.c1 = min(cols, c1 + 1)
        case .up: g.r0 = max(0, r0 - 1)
        case .down: g.r1 = min(rows, r1 + 1)
        }
        return g
    }

    // frame returns the span's frame in area with gap around it.
    public func frame(_ area: Frame, gap: Double = 0) -> Frame {
        Geometry.part(area, c0, c1, cols, r0, r1, rows, gap: gap)
    }
}

// Overlay holds the overlay's cursor picker: throw by direction and the radial menu are one picker
// that reads how far and which way the cursor moved since the trigger went down.
public enum Overlay {
    // deadZone is how far in points the cursor must move before anything is picked.
    public static let deadZone = 24.0
    // ring is the distance in points where the inner ring of targets gives way to the outer one.
    public static let ring = 160.0
    // inner lists the inner ring's actions by sector, counterclockwise from the right.
    public static let inner = [
        "right-half", "top-right", "top-half", "top-left", "left-half", "bottom-left",
        "bottom-half", "bottom-right",
    ]
    // outer lists the outer ring's actions by sector, counterclockwise from the right.
    public static let outer = [
        "last-third", "top-right-sixth", "maximize", "top-left-sixth", "first-third",
        "bottom-left-sixth", "center", "bottom-right-sixth",
    ]

    // pick returns the action for a cursor moved by dx and dy points, in top-left coordinates so up
    // is a negative dy, or nil inside the dead zone. Eight sectors of 45 degrees are centered on the
    // axes and diagonals, and a boundary belongs to the sector counterclockwise of it.
    public static func pick(dx: Double, dy: Double) -> String? {
        let d = (dx * dx + dy * dy).squareRoot()
        guard d >= deadZone else { return nil }
        var deg = atan2(-dy, dx) * 180 / .pi
        if deg < 0 {
            deg += 360
        }
        let sector = Int((deg + 22.5) / 45) % 8
        return (d < ring ? inner : outer)[sector]
    }
}

// Overlay grid actions: grid pops a grid of cells over the window's area at the overlay's grid size,
// and grid:<columns>x<rows> at a size of its own. Dragging across cells picks the span to fill.
extension Overlay {
    // gridName is the action that pops the grid at the size in the overlay choices.
    public static let gridName = "grid"
    // gridPrefix starts the action name of a grid with a size of its own, such as grid:8x6.
    public static let gridPrefix = "grid:"

    // gridSize returns the columns and rows grid action name asks for, the overlay choices' size for
    // plain grid, or nil when name is not a grid action or its size is outside gridRange.
    public static func gridSize(_ name: String, _ choices: OverlayChoices) -> (cols: Int, rows: Int)? {
        if name == gridName {
            return (choices.gridColumns, choices.gridRows)
        }
        guard name.hasPrefix(gridPrefix) else { return nil }
        let parts = name.dropFirst(gridPrefix.count).split(separator: "x", omittingEmptySubsequences: false)
        let r = OverlayChoices.gridRange
        guard parts.count == 2, let c = Int(parts[0]), let rows = Int(parts[1]), r.contains(c), r.contains(rows)
        else { return nil }
        return (c, rows)
    }
}

// HoverMode is what holding the hover modifiers does to the window under the pointer.
public enum HoverMode: Sendable {
    case move, resize
}

// HoverCorner names the corner of a window that follows the pointer while it is resized.
public enum HoverCorner: Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    // left reports whether the corner is on the window's left edge.
    var left: Bool { self == .topLeft || self == .bottomLeft }
    // top reports whether the corner is on the window's top edge.
    var top: Bool { self == .topLeft || self == .topRight }
}

// Hover moves or resizes the window under the pointer while modifiers are held and no button is down.
// Every frame is computed from where the window and pointer were when the modifiers went down, so a
// size the app refuses never builds up drift.
public enum Hover {
    // minimum is the smallest width and height in points a hover resize shrinks a window to.
    public static let minimum = (w: 160.0, h: 100.0)

    // usable reports whether mods can drive a hover: at least one of Control, Option and Command,
    // since Shift alone is held for typing and selecting.
    public static func usable(_ mods: [Modifier]) -> Bool {
        mods.contains { $0 != .shift }
    }

    // mode returns what the modifiers in m do: move when they are exactly the move set, resize when
    // they are exactly the resize set, nil otherwise. A set that is not usable, or a resize set equal
    // to the move set, does nothing.
    public static func mode(_ m: Modifiers, _ choices: OverlayChoices) -> HoverMode? {
        let held = Set(m.shortcut)
        if usable(choices.hoverMove), Set(choices.hoverMove) == held {
            return .move
        }
        if usable(choices.hoverResize), Set(choices.hoverResize) == held,
            Set(choices.hoverResize) != Set(choices.hoverMove)
        {
            return .resize
        }
        return nil
    }

    // holds reports whether the modifiers in m are exactly mods and mods can drive a drag.
    public static func holds(_ m: Modifiers, _ mods: [Modifier]) -> Bool {
        usable(mods) && Set(m.shortcut) == Set(mods)
    }

    // corner returns the corner of f nearest p, by which half of f p is in.
    public static func corner(_ f: Frame, nearest p: Point) -> HoverCorner {
        let left = p.x < f.x + f.w / 2
        let top = p.y < f.y + f.h / 2
        switch (top, left) {
        case (true, true): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    // frame returns where start goes when the pointer has moved dx and dy points since the modifiers
    // went down: moved by that much, or resized with corner following the pointer and the opposite
    // corner fixed, no smaller than minimum.
    public static func frame(_ mode: HoverMode, start: Frame, corner: HoverCorner, dx: Double, dy: Double) -> Frame {
        guard mode == .resize else {
            return Frame(x: start.x + dx, y: start.y + dy, w: start.w, h: start.h)
        }
        let w = max(minimum.w, start.w + (corner.left ? -dx : dx))
        let h = max(minimum.h, start.h + (corner.top ? -dy : dy))
        return keep(start, corner: corner, w: w, h: h)
    }

    // keep returns a frame of w by h whose corner opposite corner sits where start's does, so a size
    // the app rounds or refuses moves only the corner that follows the pointer.
    public static func keep(_ start: Frame, corner: HoverCorner, w: Double, h: Double) -> Frame {
        Frame(
            x: corner.left ? start.x + start.w - w : start.x, y: corner.top ? start.y + start.h - h : start.y, w: w,
            h: h)
    }
}
