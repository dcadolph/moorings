import MooringsCore
import MooringsEngine

// FakeBadge is a BadgeView that records what the badge showed.
public final class FakeBadge: BadgeView {
    // Call is one call the badge received.
    public enum Call: Equatable, Sendable {
        case show(Int, Frame)
        case hide
    }

    // shown is the mark the badge paints, nil when hidden.
    public private(set) var shown: BadgeMark?
    // calls records every call in order.
    public private(set) var calls: [Call] = []

    // init builds a hidden badge.
    public init() {}

    // show records the count and front and makes them the shown mark.
    public func show(_ count: Int, at front: Frame, palette: Palette) {
        calls.append(.show(count, front))
        shown = BadgeMark(count: count, front: front)
    }

    // hide records the call and clears the shown mark.
    public func hide() {
        calls.append(.hide)
        shown = nil
    }
}
