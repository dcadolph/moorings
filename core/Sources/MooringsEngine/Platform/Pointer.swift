import MooringsCore

// Pointer reads and moves the mouse pointer.
public protocol Pointer: AnyObject {
    // position is where the pointer is, in top-left screen coordinates.
    var position: Point { get }
    // buttonDown reports whether any mouse button is held.
    var buttonDown: Bool { get }
    // warp moves the pointer to p.
    func warp(_ p: Point)
}
