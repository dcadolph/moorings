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
    // snapping supplies the area maps and sizes, used off the ultrawide, and held is the set of modifier
    // names down now. The ultrawide strip rule is fixed and ignores the maps.
    // ch is the channel when the display is the ultrawide. prev is the zone the drag was last in.
    public static func zone(
        _ p: SnapPoint, _ f: Frame, _ ch: Frame? = nil, _ prev: String? = nil, snapping: SnapChoices = SnapChoices(),
        held: Set<String> = []
    ) -> String? {
        if !snapping.snapModifiers.isEmpty && !Set(snapping.snapModifiers).isSubset(of: held) {
            return nil
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

// FootprintStyle holds how the drag footprint looks and feels, each at Rectangle's default.
public struct FootprintStyle: Equatable, Sendable, Codable {
    // alpha is the footprint fill opacity.
    public var alpha: Double = 0.3
    // borderWidth is the footprint border width in points.
    public var borderWidth: Double = 2
    // fade reports whether the footprint fades in and out.
    public var fade: Bool = false
    // color is a hex color overriding the theme color, or nil to use the theme.
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
        alpha = (try? c.decodeIfPresent(Double.self, forKey: .alpha)) ?? 0.3
        borderWidth = (try? c.decodeIfPresent(Double.self, forKey: .borderWidth)) ?? 2
        fade = (try? c.decodeIfPresent(Bool.self, forKey: .fade)) ?? false
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        animationSpeed = (try? c.decodeIfPresent(Double.self, forKey: .animationSpeed)) ?? 0
        haptic = (try? c.decodeIfPresent(Bool.self, forKey: .haptic)) ?? false
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

    // init builds snap choices at their defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case landscapeSnapAreas, portraitSnapAreas, ignoredSnapAreas, snapModifiers, snapBeforeReachingEdges
        case edgeMarginTop, edgeMarginBottom, edgeMarginLeft, edgeMarginRight, cornerSize, shortEdgeSize, footprint
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
