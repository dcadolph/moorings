// SnapPoint is a cursor position in global top-left coordinates, in points.
public struct SnapPoint: Equatable, Sendable {
    // x is the horizontal position.
    public var x: Double
    // y is the vertical position.
    public var y: Double

    // init builds a point.
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

// SnapDrop is where a dragged window lands: an action zone, or a slot its app parks in.
public enum SnapDrop: Equatable, Sendable {
    case zone(String)
    case park(String)
}

// Snap holds the drag zone math. Every function is pure.
public enum Snap {
    // margin is how close in points the cursor must come to an edge.
    public static let margin = 5.0

    // corner is how far in points from a corner the quarter zones reach.
    public static let corner = 20.0

    // short is how far in points from a corner the half zones on an edge reach.
    public static let short = 145.0

    // third returns the third under x across the span ox to ox+w. The center third becomes two
    // thirds when the drag came from a side third.
    public static func third(_ x: Double, _ ox: Double, _ w: Double, _ prev: String? = nil) -> String {
        let i = max(0, min(2, Int(((x - ox) * 3 / w).rounded(.down))))
        if i == 0 {
            return "first-third"
        } else if i == 2 {
            return "last-third"
        } else if prev == "first-third" || prev == "first-two-thirds" {
            return "first-two-thirds"
        } else if prev == "last-third" || prev == "last-two-thirds" {
            return "last-two-thirds"
        }
        return "center-third"
    }

    // stripSide returns the side whose strip holds p on the ultrawide with full frame f and channel
    // ch, or nil over the channel. The last margin points of the display stand in for a side with
    // no strip, so its edge still snaps and parks.
    public static func stripSide(_ p: SnapPoint, _ f: Frame, _ ch: Frame) -> Side? {
        if p.x < max(ch.x, f.x + margin) {
            return .left
        } else if p.x >= min(ch.x + ch.w, f.x + f.w - margin) {
            return .right
        }
        return nil
    }

    // zone returns the action a window dropped at p gets on a display whose full frame is f, or nil.
    // snapping supplies the custom areas, which come first, the area maps and sizes, all used off the
    // ultrawide, and held is the set of modifier names down now. The ultrawide strip rule is fixed and
    // ignores the custom areas and the maps.
    // ch is the channel when the display is the ultrawide. prev is the zone the drag was last in.
    public static func zone(
        _ p: SnapPoint, _ f: Frame, _ ch: Frame? = nil, _ prev: String? = nil, snapping: SnapChoices = SnapChoices(),
        held: Set<String> = []
    ) -> String? {
        if !snapping.snapModifiers.isEmpty && !Set(snapping.snapModifiers).isSubset(of: held) {
            return nil
        }
        if ch == nil, let area = snapping.customAreas.first(where: { !$0.action.isEmpty && $0.contains(p, f) }) {
            return area.action
        }
        let l = p.x - f.x
        let r = f.x + f.w - p.x
        let t = p.y - f.y
        let b = f.y + f.h - p.y
        let atTop = t < margin
        let atBottom = b <= margin
        if let ch {
            if let side = stripSide(p, f, ch) {
                if t < short {
                    return "top-\(side.rawValue)"
                } else if b <= short {
                    return "bottom-\(side.rawValue)"
                }
                return "\(side.rawValue)-half"
            }
            if atTop {
                return "maximize"
            } else if atBottom {
                return third(p.x, ch.x, ch.w, prev)
            }
            return nil
        }
        let m = snapping
        let areas = f.h > f.w ? m.portraitSnapAreas : m.landscapeSnapAreas
        let edge = m.snapBeforeReachingEdges
        let atLeft = l < m.edgeMarginLeft + edge
        let atRight = r <= m.edgeMarginRight + edge
        let atTopEdge = t < m.edgeMarginTop + edge
        let atBottomEdge = b <= m.edgeMarginBottom + edge
        let cs = m.cornerSize
        let ss = m.shortEdgeSize
        if atLeft || atRight {
            let side = atLeft ? "left" : "right"
            if t < cs {
                return m.resolve("top-\(side)", areas, p, f, prev, side)
            } else if b <= cs {
                return m.resolve("bottom-\(side)", areas, p, f, prev, side)
            }
            return m.resolve(side, areas, p, f, prev, side, t < ss ? "top" : b <= ss ? "bottom" : nil)
        }
        if atTopEdge || atBottomEdge {
            let row = atTopEdge ? "top" : "bottom"
            if l < cs {
                return m.resolve("\(row)-left", areas, p, f, prev, "left")
            } else if r <= cs {
                return m.resolve("\(row)-right", areas, p, f, prev, "right")
            }
            return m.resolve(row, areas, p, f, prev, nil, l < ss || r <= ss ? row : nil)
        }
        return nil
    }

    // park returns the slot key, such as left-top, of the strip half under p on the ultrawide with
    // full frame f and channel ch, or nil over the channel.
    public static func park(_ p: SnapPoint, _ f: Frame, _ ch: Frame) -> String? {
        guard let side = stripSide(p, f, ch) else {
            return nil
        }
        return "\(side.rawValue)-\(p.y < f.y + f.h / 2 ? "top" : "bottom")"
    }

    // drop returns what a drop at p lands on. With option held on the ultrawide it is a park slot,
    // and only for a parkable window. A pinned or cast-off window has no other zones.
    public static func drop(
        _ p: SnapPoint, _ f: Frame, _ ch: Frame? = nil, prev: String? = nil, option: Bool = false,
        parkable: Bool = false, pinned: Bool = false, castOff: Bool = false, snapping: SnapChoices = SnapChoices(),
        held: Set<String> = []
    ) -> SnapDrop? {
        if let ch, option {
            guard parkable, let key = park(p, f, ch) else {
                return nil
            }
            return .park(key)
        }
        if pinned || castOff {
            return nil
        }
        return zone(p, f, ch, prev, snapping: snapping, held: held).map { .zone($0) }
    }
}

// FootprintStyle holds how the drag footprint looks and feels, each at today's look or Rectangle's default.
public struct FootprintStyle: Equatable, Sendable, Codable {
    // fadeSeconds is the fade time at an animation speed of 1.
    public static let fadeSeconds = 0.2

    // alpha is the footprint fill opacity.
    public var alpha: Double = Palette.footprintFillAlpha
    // borderWidth is the footprint border width in points.
    public var borderWidth: Double = 2
    // fade reports whether the footprint fades in and out.
    public var fade: Bool = false
    // color is a hex color overriding the palette's accent, or nil to use the accent.
    public var color: String? = nil
    // animationSpeed is the footprint animation duration multiplier, 0 for the system default.
    public var animationSpeed: Double = 0
    // haptic reports whether a snap gives haptic feedback.
    public var haptic: Bool = false

    // init builds a style at its defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case alpha, borderWidth, fade, color, animationSpeed, haptic
    }

    // init decodes a saved style, keeping the default for anything missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alpha = (try? c.decodeIfPresent(Double.self, forKey: .alpha)) ?? Palette.footprintFillAlpha
        borderWidth = (try? c.decodeIfPresent(Double.self, forKey: .borderWidth)) ?? 2
        fade = (try? c.decodeIfPresent(Bool.self, forKey: .fade)) ?? false
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        animationSpeed = (try? c.decodeIfPresent(Double.self, forKey: .animationSpeed)) ?? 0
        haptic = (try? c.decodeIfPresent(Bool.self, forKey: .haptic)) ?? false
    }

    // tints returns the footprint fill and stroke on palette: the accent, or color when it parses, with the
    // fill at alpha and the stroke at the palette's stroke opacity.
    public func tints(_ palette: Palette) -> (fill: Tint, stroke: Tint) {
        let base = color.flatMap { RGB(hex: $0) } ?? palette.accent
        return (Tint(color: base, alpha: max(0, min(1, alpha))), Tint(color: base, alpha: Palette.footprintStrokeAlpha))
    }

    // fadeTime is the fade time in seconds, 0 when fade is off. animationSpeed scales fadeSeconds, 0 keeps it.
    public var fadeTime: Double {
        fade ? Self.fadeSeconds * (animationSpeed > 0 ? animationSpeed : 1) : 0
    }
}

// SnapChoices holds the drag snap configuration, each at today's built-in behavior or Rectangle's default.
// An area maps to an action name, or to a compound: side-halves, maximize-halves, thirds-halves, top-sixths,
// bottom-sixths. An empty or missing value disables the area.
public struct SnapChoices: Equatable, Sendable, Codable {
    // defaultAreas is the built-in area map, shared by landscape and portrait displays.
    public static let defaultAreas: [String: String] = [
        "top-left": "top-left", "top": "maximize-halves", "top-right": "top-right",
        "left": "side-halves", "right": "side-halves",
        "bottom-left": "bottom-left", "bottom": "thirds-halves", "bottom-right": "bottom-right",
    ]

    // landscapeSnapAreas maps an area name to its action on a landscape display.
    public var landscapeSnapAreas: [String: String] = SnapChoices.defaultAreas
    // portraitSnapAreas maps an area name to its action on a portrait display.
    public var portraitSnapAreas: [String: String] = SnapChoices.defaultAreas
    // ignoredSnapAreas lists area names that never snap, whatever the maps say.
    public var ignoredSnapAreas: [String] = []
    // snapModifiers lists the modifier names (shift, control, option, command) that must be held to snap.
    public var snapModifiers: [String] = []
    // snapBeforeReachingEdges is the extra distance in points before an edge at which snapping starts.
    public var snapBeforeReachingEdges: Double = 0
    // edgeMarginTop is how close in points the cursor must come to the top edge.
    public var edgeMarginTop: Double = 5
    // edgeMarginBottom is how close in points the cursor must come to the bottom edge.
    public var edgeMarginBottom: Double = 5
    // edgeMarginLeft is how close in points the cursor must come to the left edge.
    public var edgeMarginLeft: Double = 5
    // edgeMarginRight is how close in points the cursor must come to the right edge.
    public var edgeMarginRight: Double = 5
    // cornerSize is how far in points from a corner the quarter areas reach.
    public var cornerSize: Double = 20
    // shortEdgeSize is how far in points from a corner the half areas on an edge reach.
    public var shortEdgeSize: Double = 145
    // footprint is the footprint style.
    public var footprint: FootprintStyle = FootprintStyle()
    // customAreas lists the areas the owner drew, checked in order before the edge areas.
    public var customAreas: [CustomSnapArea] = []
    // snapPanel reports whether pausing during a drag shows a panel of targets near the cursor.
    public var snapPanel: Bool = false
    // panelActions lists the snap panel's targets, left to right.
    public var panelActions: [String] = SnapPanel.defaultActions

    // init builds snap choices at their defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case landscapeSnapAreas, portraitSnapAreas, ignoredSnapAreas, snapModifiers, snapBeforeReachingEdges
        case edgeMarginTop, edgeMarginBottom, edgeMarginLeft, edgeMarginRight, cornerSize, shortEdgeSize, footprint
        case customAreas, snapPanel, panelActions
    }

    // init decodes saved snap choices, keeping the default for anything missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        landscapeSnapAreas = (try? c.decodeIfPresent([String: String].self, forKey: .landscapeSnapAreas))
            ?? SnapChoices.defaultAreas
        portraitSnapAreas = (try? c.decodeIfPresent([String: String].self, forKey: .portraitSnapAreas))
            ?? SnapChoices.defaultAreas
        ignoredSnapAreas = (try? c.decodeIfPresent([String].self, forKey: .ignoredSnapAreas)) ?? []
        snapModifiers = (try? c.decodeIfPresent([String].self, forKey: .snapModifiers)) ?? []
        snapBeforeReachingEdges = (try? c.decodeIfPresent(Double.self, forKey: .snapBeforeReachingEdges)) ?? 0
        edgeMarginTop = (try? c.decodeIfPresent(Double.self, forKey: .edgeMarginTop)) ?? 5
        edgeMarginBottom = (try? c.decodeIfPresent(Double.self, forKey: .edgeMarginBottom)) ?? 5
        edgeMarginLeft = (try? c.decodeIfPresent(Double.self, forKey: .edgeMarginLeft)) ?? 5
        edgeMarginRight = (try? c.decodeIfPresent(Double.self, forKey: .edgeMarginRight)) ?? 5
        cornerSize = (try? c.decodeIfPresent(Double.self, forKey: .cornerSize)) ?? 20
        shortEdgeSize = (try? c.decodeIfPresent(Double.self, forKey: .shortEdgeSize)) ?? 145
        footprint = (try? c.decodeIfPresent(FootprintStyle.self, forKey: .footprint)) ?? FootprintStyle()
        customAreas = (try? c.decodeIfPresent([CustomSnapArea].self, forKey: .customAreas)) ?? []
        snapPanel = (try? c.decodeIfPresent(Bool.self, forKey: .snapPanel)) ?? false
        panelActions = (try? c.decodeIfPresent([String].self, forKey: .panelActions)) ?? SnapPanel.defaultActions
    }

    // resolve returns the action for area under the map, or nil when the area is ignored or unmapped. short
    // is the half the cursor sits in along the edge, or nil, and side is the side for compounds that need it.
    func resolve(
        _ area: String, _ areas: [String: String], _ p: SnapPoint, _ f: Frame, _ prev: String?, _ side: String?,
        _ short: String? = nil
    ) -> String? {
        guard !ignoredSnapAreas.contains(area), let value = areas[area], !value.isEmpty else {
            return nil
        }
        switch value {
        case "side-halves":
            return short.map { "\($0)-half" } ?? "\(side ?? area)-half"
        case "maximize-halves":
            return short.map { "\($0)-half" } ?? "maximize"
        case "thirds-halves":
            return short.map { "\($0)-half" } ?? Snap.third(p.x, f.x, f.w, prev)
        case "top-sixths", "bottom-sixths":
            let row = value == "top-sixths" ? "top" : "bottom"
            let col = ["left", "center", "right"][max(0, min(2, Int(((p.x - f.x) * 3 / f.w).rounded(.down))))]
            return "\(row)-\(col)-sixth"
        default:
            return value
        }
    }
}

// CustomSnapArea is a snap area the owner draws: a rectangle as shares of a display's full frame, each
// from 0 to 1, and the action a window dropped in it gets.
public struct CustomSnapArea: Equatable, Sendable, Codable {
    // x is the left edge as a share of the display's width.
    public var x: Double
    // y is the top edge as a share of the display's height.
    public var y: Double
    // w is the width as a share of the display's width.
    public var w: Double
    // h is the height as a share of the display's height.
    public var h: Double
    // action is the action a window dropped here gets, empty to turn the area off.
    public var action: String

    // init builds an area.
    public init(x: Double, y: Double, w: Double, h: Double, action: String) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.action = action
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case x, y, w, h, action
    }

    // init decodes an area, keeping 0 or empty for anything missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? c.decodeIfPresent(Double.self, forKey: .x)) ?? 0
        y = (try? c.decodeIfPresent(Double.self, forKey: .y)) ?? 0
        w = (try? c.decodeIfPresent(Double.self, forKey: .w)) ?? 0
        h = (try? c.decodeIfPresent(Double.self, forKey: .h)) ?? 0
        action = (try? c.decodeIfPresent(String.self, forKey: .action)) ?? ""
    }

    // frame returns the area on a display whose full frame is f.
    public func frame(_ f: Frame) -> Frame {
        Frame(x: f.x + x * f.w, y: f.y + y * f.h, w: w * f.w, h: h * f.h)
    }

    // contains reports whether p lies in the area on a display whose full frame is f.
    public func contains(_ p: SnapPoint, _ f: Frame) -> Bool {
        let r = frame(f)
        return r.w > 0 && r.h > 0 && p.x >= r.x && p.x < r.x + r.w && p.y >= r.y && p.y < r.y + r.h
    }
}

// SnapPanel holds the snap panel's layout: a row of targets that appears near the cursor when a drag
// pauses. Every function is pure.
public enum SnapPanel {
    // defaultActions lists the targets a new panel offers.
    public static let defaultActions = ["left-half", "maximize", "right-half", "first-third", "center-third", "last-third"]
    // dwellSeconds is how long the cursor must pause during a drag before the panel appears.
    public static let dwellSeconds = 0.3
    // still is the most in points the cursor may move and still count as paused.
    public static let still = 4.0
    // cellWidth and cellHeight are a target's size in points.
    public static let cellWidth = 64.0
    public static let cellHeight = 44.0
    // spacing is the room in points between targets, and padding the room around them.
    public static let spacing = 6.0
    public static let padding = 8.0
    // offset is how far in points above the cursor the panel's bottom sits, or below it when there is
    // no room above.
    public static let offset = 48.0

    // layout returns the panel's frame and its count targets' frames for a pause at p on a display whose
    // full frame is f: centered over the cursor, above it when it fits and below it otherwise, and kept
    // on the display.
    public static func layout(_ count: Int, at p: SnapPoint, screen f: Frame) -> (panel: Frame, cells: [Frame]) {
        let n = max(0, count)
        let w = Double(n) * cellWidth + Double(max(0, n - 1)) * spacing + 2 * padding
        let h = cellHeight + 2 * padding
        var x = p.x - w / 2
        x = min(max(x, f.x), f.x + f.w - w)
        var y = p.y - offset - h
        if y < f.y {
            y = p.y + offset
        }
        y = min(max(y, f.y), f.y + f.h - h)
        let cells = (0..<n).map { i in
            Frame(x: x + padding + Double(i) * (cellWidth + spacing), y: y + padding, w: cellWidth, h: cellHeight)
        }
        return (Frame(x: x, y: y, w: w, h: h), cells)
    }

    // hit returns the index of the target under p, nil when none is.
    public static func hit(_ p: SnapPoint, _ cells: [Frame]) -> Int? {
        cells.firstIndex { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h }
    }
}
