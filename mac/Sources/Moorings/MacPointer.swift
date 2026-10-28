import AppKit

import MooringsCore
import MooringsEngine

// MacPointer is the Mac Pointer: the mouse location from NSEvent, flipped to top-left coordinates.
@MainActor
final class MacPointer: @preconcurrency Pointer {
    // position is where the pointer is, measured from the primary screen's top-left corner.
    var position: Point {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        return Point(x: loc.x, y: primary - loc.y)
    }

    // buttonDown reports whether any mouse button is held.
    var buttonDown: Bool { NSEvent.pressedMouseButtons != 0 }

    // warp moves the pointer to p without posting a mouse event.
    func warp(_ p: Point) {
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: p.y))
    }
}
