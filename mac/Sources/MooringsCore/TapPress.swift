// TapPress tracks the primary button from press to release as the mouse tap saw them, so a release
// the tap missed while the system had it turned off does not leave a press open.
public struct TapPress: Equatable, Sendable {
    // End is how a press ended: not at all, as a click the tap let through, or as one it swallowed.
    public enum End: Equatable, Sendable {
        case none
        case plain
        case swallowed
    }

    // held reports whether the button went down and the tap has not seen it come up.
    public private(set) var held = false
    // swallowed reports whether the held press was swallowed, so its release must be too.
    public private(set) var swallowed = false

    // init makes the state of a button that is up.
    public init() {}

    // pressing is called as the button goes down, before the press is handled, and returns how the
    // previous press ended when the tap never saw its release.
    public mutating func pressing() -> End {
        end()
    }

    // down records a press once it is handled, swallowed or not.
    public mutating func down(swallow: Bool) {
        held = true
        swallowed = swallow
    }

    // up records a release and returns how the press ended. A release with no press seen counts as
    // a plain click, so it always reaches the app.
    public mutating func up() -> End {
        let ended = end()
        return ended == .none ? .plain : ended
    }

    // recover is called after the system turned the tap back on, with whether the button is down
    // now, and returns how the press ended when its release came while the tap was off.
    public mutating func recover(buttonDown: Bool) -> End {
        buttonDown ? .none : end()
    }

    // end closes the held press and returns how it ended.
    private mutating func end() -> End {
        defer {
            held = false
            swallowed = false
        }
        guard held else { return .none }
        return swallowed ? .swallowed : .plain
    }
}
