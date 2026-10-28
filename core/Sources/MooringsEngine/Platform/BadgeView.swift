import MooringsCore

// BadgeMark is what a stack badge shows: the count and the front window it sits on.
public struct BadgeMark: Equatable, Sendable {
    // count is the number of windows in the stack.
    public var count: Int
    // front is the frame of the stack's front window, whose top-right corner holds the badge.
    public var front: Frame

    // init builds a mark.
    public init(count: Int, front: Frame) {
        self.count = count
        self.front = front
    }
}

// BadgeView paints the stack badge, the count at the top-right corner of a stack's front window.
public protocol BadgeView: AnyObject {
    // show paints count at the top-right corner of front; a second show moves it.
    func show(_ count: Int, at front: Frame, palette: Palette)
    // hide takes the badge off screen.
    func hide()
    // shown is the mark the badge paints, nil when hidden.
    var shown: BadgeMark? { get }
}
