import AppKit

import MooringsCore
import MooringsEngine

// MacPointer is the Mac Pointer: the mouse location from NSEvent, flipped to top-left coordinates,
// and event monitors that follow it while the engine tracks it.
@MainActor
final class MacPointer: @preconcurrency Pointer {
    // tracked lists the events that make the pointer worth reading while it is tracked: a move, and a
    // button let go, since a held button stops a stashed window sliding out.
    private static let tracked: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp]

    // monitors watch the pointer over other apps and Moorings while it is tracked.
    private var monitors: [Any] = []

    // position is where the pointer is, measured from the primary screen's top-left corner.
    var position: Point {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        return Point(x: loc.x, y: primary - loc.y)
    }

    // buttonDown reports whether any mouse button is held.
    var buttonDown: Bool { NSEvent.pressedMouseButtons != 0 }

    // primaryDown reports whether the primary mouse button is held.
    var primaryDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    // warp moves the pointer to p without posting a mouse event.
    func warp(_ p: Point) {
        CGWarpMouseCursorPosition(CGPoint(x: p.x, y: p.y))
    }

    // track replaces the monitors with ones that call moved on each tracked event, or removes them
    // when moved is nil.
    func track(_ moved: (() -> Void)?) {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors = []
        guard let moved else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: Self.tracked,
            handler: { _ in
                MainActor.assumeIsolated { moved() }
            })
        {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: Self.tracked,
            handler: { event in
                MainActor.assumeIsolated { moved() }
                return event
            })
        {
            monitors.append(m)
        }
    }
}
