// MoveStep is one Accessibility write a window move makes.
public enum MoveStep: Equatable, Sendable {
    case size
    case position
}

// MoveSteps decides which writes a move needs, so a move that keeps the size or the origin makes one
// write instead of three.
public enum MoveSteps {
    // tolerance is how far in points two edges or sizes may differ and still count as equal.
    public static let tolerance = 0.5

    // full sets the size first and again last, so a window crossing displays lands at the size asked
    // for even when the system squeezes it on the way.
    public static let full: [MoveStep] = [.size, .position, .size]

    // steps returns the writes that move a window from current to target. Without a current frame,
    // or when both the size and the origin change, it returns full. A target with the current size
    // needs only its position, and one with the current origin needs only its size.
    public static func steps(from current: Frame?, to target: Frame) -> [MoveStep] {
        guard let current else { return full }
        let sameSize = abs(current.w - target.w) <= tolerance && abs(current.h - target.h) <= tolerance
        let sameOrigin = abs(current.x - target.x) <= tolerance && abs(current.y - target.y) <= tolerance
        switch (sameSize, sameOrigin) {
        case (true, true): return []
        case (true, false): return [.position]
        case (false, true): return [.size]
        case (false, false): return full
        }
    }
}
