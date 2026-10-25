import Foundation

// OverlayTrigger names the key that brings up the overlay while it is held.
public enum OverlayTrigger: String, Codable, CaseIterable, Sendable {
    case none, rightOption, rightCommand, rightControl, fn

    // control, option and command are the device-independent modifier bits of a CGEventFlags value.
    static let control: UInt64 = 0x40000
    static let option: UInt64 = 0x80000
    static let command: UInt64 = 0x100000

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

    // bit is the flag bit that is set only while the trigger's own key is down: the device-dependent
    // bit of the right-hand modifier, or the secondary function bit for Fn. None has no bit.
    public var bit: UInt64 {
        switch self {
        case .none: 0
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightControl: 0x2000
        case .fn: 0x800000
        }
    }

    // own is the device-independent modifier bit the trigger's key also sets, 0 for Fn and None.
    var own: UInt64 {
        switch self {
        case .rightOption: Self.option
        case .rightCommand: Self.command
        case .rightControl: Self.control
        case .none, .fn: 0
        }
    }

    // held reports whether flags show the trigger down with no Control, Option or Command besides
    // the trigger's own. Shift may be down, since it grows the grid.
    public func held(_ flags: UInt64) -> Bool {
        guard self != .none, flags & bit != 0 else { return false }
        let others = (Self.control | Self.option | Self.command) & ~own
        return flags & others == 0
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

    // gridRange bounds the grid columns and rows.
    public static let gridRange = 1...12

    // init builds overlay choices at the defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case trigger, gridColumns, gridRows
    }

    // init decodes overlay choices, keeping the default for any field missing or unreadable and
    // clamping the grid size to gridRange.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = Self.gridRange
        trigger = (try? c.decodeIfPresent(OverlayTrigger.self, forKey: .trigger)) ?? .none
        gridColumns = min(r.upperBound, max(r.lowerBound, (try? c.decodeIfPresent(Int.self, forKey: .gridColumns)) ?? 6))
        gridRows = min(r.upperBound, max(r.lowerBound, (try? c.decodeIfPresent(Int.self, forKey: .gridRows)) ?? 4))
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
    public static let inner = ["right-half", "top-right", "top-half", "top-left", "left-half", "bottom-left",
                               "bottom-half", "bottom-right"]
    // outer lists the outer ring's actions by sector, counterclockwise from the right.
    public static let outer = ["last-third", "top-right-sixth", "maximize", "top-left-sixth", "first-third",
                               "bottom-left-sixth", "center", "bottom-right-sixth"]

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
