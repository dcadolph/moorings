import MooringsCore
import MooringsEngine

// FakePointer is a Pointer that sits where it was last warped.
public final class FakePointer: Pointer {
    // position is where the pointer is.
    public var position: Point
    // buttonDown reports whether a test holds a button.
    public var buttonDown = false
    // warps records every warp in order.
    public private(set) var warps: [Point] = []

    // init builds a pointer at position.
    public init(_ position: Point = Point(x: 100, y: 100)) {
        self.position = position
    }

    // warp moves the pointer to p.
    public func warp(_ p: Point) {
        warps.append(p)
        position = p
    }
}
