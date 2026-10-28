import MooringsCore

// Pointer reads and moves the mouse pointer.
public protocol Pointer: AnyObject {
    // position is where the pointer is, in top-left screen coordinates.
    var position: Point { get }
    // buttonDown reports whether any mouse button is held.
    var buttonDown: Bool { get }
    // primaryDown reports whether the primary mouse button is held, which leaves dragged pins alone.
    var primaryDown: Bool { get }
    // warp moves the pointer to p.
    func warp(_ p: Point)
    // track delivers pointer moves and button releases to moved while it is set and stops when nil;
    // the engine sets it only while a window is stashed, so a still pointer costs nothing.
    func track(_ moved: (() -> Void)?)
}
