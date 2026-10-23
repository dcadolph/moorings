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
    // ch is the channel when the display is the ultrawide. prev is the zone the drag was last in.
    public static func zone(_ p: SnapPoint, _ f: Frame, _ ch: Frame? = nil, _ prev: String? = nil) -> String? {
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
        if l < margin || r <= margin {
            let side = l < margin ? "left" : "right"
            if t < corner {
                return "top-\(side)"
            } else if b <= corner {
                return "bottom-\(side)"
            } else if t < short {
                return "top-half"
            } else if b <= short {
                return "bottom-half"
            }
            return "\(side)-half"
        }
        if atTop || atBottom {
            let row = atTop ? "top" : "bottom"
            if l < corner {
                return "\(row)-left"
            } else if r <= corner {
                return "\(row)-right"
            } else if l < short || r <= short {
                return "\(row)-half"
            }
            return atTop ? "maximize" : third(p.x, f.x, f.w, prev)
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
        parkable: Bool = false, pinned: Bool = false, castOff: Bool = false
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
        return zone(p, f, ch, prev).map { .zone($0) }
    }
}
