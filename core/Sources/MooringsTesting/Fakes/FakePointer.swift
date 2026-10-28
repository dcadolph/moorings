import MooringsCore
import MooringsEngine

// FakePointer is a Pointer that sits where it was last warped or moved, and tells the tracker of each
// move a test makes. A warp, like the platforms' own, tells no one.
public final class FakePointer: Pointer {
    // position is where the pointer is.
    public var position: Point
    // buttonDown reports whether a test holds a button.
    public var buttonDown = false
    // primaryDown reports whether a test holds the primary button.
    public var primaryDown = false
    // warps records every warp in order.
    public private(set) var warps: [Point] = []
    // tracker is told each move while it is set.
    public private(set) var tracker: (() -> Void)?
    // tracks records whether each track call set a tracker, in order.
    public private(set) var tracks: [Bool] = []

    // init builds a pointer at position.
    public init(_ position: Point = Point(x: 100, y: 100)) {
        self.position = position
    }

    // warp moves the pointer to p.
    public func warp(_ p: Point) {
        warps.append(p)
        position = p
    }

    // track keeps moved as the tracker, or stops tracking when nil.
    public func track(_ moved: (() -> Void)?) {
        tracks.append(moved != nil)
        tracker = moved
    }

    // move puts the pointer at p as a person would and tells the tracker.
    public func move(to p: Point) {
        position = p
        tracker?()
    }
}
