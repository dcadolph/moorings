import Foundation

// StashEdge is a screen edge a window can be stashed at. The top edge is not one: macOS keeps a
// window's title bar below the menu bar, so a window cannot be parked above the screen.
public enum StashEdge: String, Codable, CaseIterable, Sendable {
    case left, right, bottom
}

// Stashed is one stashed window: where it was before, the edge it parks at, and its parked and
// shown frames.
public struct Stashed: Equatable, Sendable {
    // id is the window's id.
    public var id: WindowID
    // original is the window's frame before it was stashed, where unstashing puts it back.
    public var original: Frame
    // edge is the edge the window parks at.
    public var edge: StashEdge
    // hidden is the parked frame, mostly off screen.
    public var hidden: Frame
    // shown is the frame the window slides out to, against the edge and fully on screen.
    public var shown: Frame
    // out reports whether the window is slid out.
    public var out: Bool = false
    // restSince is when the pointer came to rest on the sliver, nil while it is elsewhere.
    public var restSince: Double?
    // armed reports whether the pointer has been off the sliver since the stash, so a window stashed
    // by a drag that let go on its own sliver does not slide straight back out.
    public var armed: Bool = false

    // init builds a stashed window.
    public init(id: WindowID, original: Frame, edge: StashEdge, hidden: Frame, shown: Frame) {
        self.id = id
        self.original = original
        self.edge = edge
        self.hidden = hidden
        self.shown = shown
    }
}

// StashHover is what the pointer asks of a stashed window: slide it out, slide it back, or nothing.
public enum StashHover: Equatable, Sendable {
    case none, slideOut, slideBack
}

// Stash holds the stash frame math and the hover decision. Every function is pure.
public enum Stash {
    // sliver is how many points of a parked window stay on screen.
    public static let sliver = 12.0
    // restSeconds is how long the pointer must stay on the sliver before the window slides out.
    public static let restSeconds = 0.15
    // slack is how far in points the pointer may stray outside a slid-out window before it slides back.
    public static let slack = 4.0
    // mostlyHidden is the largest share of a window's area that may stay on screen for it to count as
    // parked, so a move macOS refused is caught.
    public static let mostlyHidden = 0.25

    // edges returns the edges of screen a window can park at: those with no other display touching
    // them, since a parked window would show on the neighbor, minus blocked.
    public static func edges(_ screen: Frame, others: [Frame], blocked: Set<StashEdge> = []) -> Set<StashEdge> {
        let t = Actions.tolerance
        let rows = others.filter { $0.y < screen.y + screen.h && screen.y < $0.y + $0.h }
        let cols = others.filter { $0.x < screen.x + screen.w && screen.x < $0.x + $0.w }
        var out: Set<StashEdge> = []
        if !rows.contains(where: { abs($0.x + $0.w - screen.x) <= t }) {
            out.insert(.left)
        }
        if !rows.contains(where: { abs($0.x - (screen.x + screen.w)) <= t }) {
            out.insert(.right)
        }
        if !cols.contains(where: { abs($0.y - (screen.y + screen.h)) <= t }) {
            out.insert(.bottom)
        }
        return out.subtracting(blocked)
    }

    // edge returns the edge of area nearest w's center among allowed, nil when none is allowed. A tie
    // goes to left, then right, then bottom.
    public static func edge(_ w: Frame, area: Frame, allowed: Set<StashEdge>) -> StashEdge? {
        let cx = w.x + w.w / 2
        let cy = w.y + w.h / 2
        let distance: [StashEdge: Double] = [.left: cx - area.x, .right: area.x + area.w - cx, .bottom: area.y + area.h - cy]
        return StashEdge.allCases.filter { allowed.contains($0) }.min { distance[$0, default: 0] < distance[$1, default: 0] }
    }

    // shown returns w slid out against edge of area, inside area and no larger than it. A bottom
    // window keeps its x inside span, the part of area it may use.
    public static func shown(_ w: Frame, _ edge: StashEdge, area: Frame, span: Frame? = nil) -> Frame {
        var f = w
        f.w = min(f.w, area.w)
        f.h = min(f.h, area.h)
        f.x = min(max(f.x, area.x), area.x + area.w - f.w)
        f.y = min(max(f.y, area.y), area.y + area.h - f.h)
        switch edge {
        case .left:
            f.x = area.x
        case .right:
            f.x = area.x + area.w - f.w
        case .bottom:
            f.y = area.y + area.h - f.h
            if let s = span {
                f.w = min(f.w, s.w)
                f.x = min(max(f.x, s.x), s.x + s.w - f.w)
            }
        }
        return f
    }

    // hidden returns the slid-out frame shown parked at edge of area, with sliver points left inside it.
    public static func hidden(_ shown: Frame, _ edge: StashEdge, area: Frame) -> Frame {
        var f = shown
        switch edge {
        case .left: f.x = area.x - f.w + sliver
        case .right: f.x = area.x + area.w - sliver
        case .bottom: f.y = area.y + area.h - sliver
        }
        return f
    }

    // stash returns window w stashed at the edge of area nearest it among allowed, nil when none is
    // allowed.
    public static func stash(_ id: WindowID, _ w: Frame, area: Frame, allowed: Set<StashEdge>, span: Frame? = nil)
        -> Stashed? {
        guard let edge = edge(w, area: area, allowed: allowed) else { return nil }
        let out = shown(w, edge, area: area, span: span)
        return Stashed(id: id, original: w, edge: edge, hidden: hidden(out, edge, area: area), shown: out)
    }

    // parked reports whether frame, where the window really landed, leaves at most mostlyHidden of it
    // inside screen, so a stash macOS refused can be undone.
    public static func parked(_ frame: Frame, screen: Frame) -> Bool {
        let w = max(0, min(frame.x + frame.w, screen.x + screen.w) - max(frame.x, screen.x))
        let h = max(0, min(frame.y + frame.h, screen.y + screen.h) - max(frame.y, screen.y))
        guard frame.w > 0, frame.h > 0 else { return false }
        return w * h <= mostlyHidden * frame.w * frame.h
    }

    // sliverRect returns the part of the parked frame hidden left inside screen.
    public static func sliverRect(_ hidden: Frame, screen: Frame) -> Frame {
        let x0 = max(hidden.x, screen.x)
        let y0 = max(hidden.y, screen.y)
        let x1 = min(hidden.x + hidden.w, screen.x + screen.w)
        let y1 = min(hidden.y + hidden.h, screen.y + screen.h)
        return Frame(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    // hover decides what the pointer at p at time now asks of s on screen, and updates its rest time.
    // A parked window slides out once the pointer has stayed on its sliver for restSeconds, after it
    // has been off the sliver once since the stash. A slid-out
    // window slides back once the pointer leaves it by more than slack. Nothing happens while a mouse
    // button is held.
    public static func hover(_ s: inout Stashed, _ p: Point, screen: Frame, now: Double, mouseHeld: Bool) -> StashHover {
        guard !mouseHeld else {
            s.restSince = nil
            return .none
        }
        if s.out {
            let f = s.shown
            let inside = p.x >= f.x - slack && p.x <= f.x + f.w + slack && p.y >= f.y - slack && p.y <= f.y + f.h + slack
            return inside ? .none : .slideBack
        }
        let r = sliverRect(s.hidden, screen: screen)
        guard r.w > 0, r.h > 0, p.x >= r.x, p.x <= r.x + r.w, p.y >= r.y, p.y <= r.y + r.h else {
            s.restSince = nil
            s.armed = true
            return .none
        }
        guard s.armed else { return .none }
        guard let since = s.restSince else {
            s.restSince = now
            return .none
        }
        return now - since >= restSeconds ? .slideOut : .none
    }
}
