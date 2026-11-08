import WinSDK

import MooringsCore
import MooringsEngine

// WinPointer is the Windows Pointer: GetCursorPos, the mouse buttons from GetAsyncKeyState, and
// SetCursorPos, all in the virtual desktop's coordinates the store uses. The mouse hook feeds moved.
final class WinPointer: Pointer {
    // moved is told each pointer move and button release while the engine tracks the pointer.
    private(set) var moved: (() -> Void)?
    // buttons are VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1 and VK_XBUTTON2.
    private static let buttons: [Int32] = [0x01, 0x02, 0x04, 0x05, 0x06]

    // hooked is the point of the hook message being handled, which position reads, since a hook sees a
    // move before Windows moves the cursor.
    var hooked: Point?

    // position is where the pointer is, the origin when it cannot be read.
    var position: Point {
        if let hooked {
            return hooked
        }
        var p = POINT()
        guard GetCursorPos(&p) else { return Point(x: 0, y: 0) }
        return Point(x: Double(p.x), y: Double(p.y))
    }

    // buttonDown reports whether any mouse button is held.
    var buttonDown: Bool {
        Self.buttons.contains { GetAsyncKeyState($0) < 0 }
    }

    // primaryDown reports whether the left mouse button is held.
    var primaryDown: Bool {
        GetAsyncKeyState(Self.buttons[0]) < 0
    }

    // warp moves the pointer to p, rounded to a pixel.
    func warp(_ p: Point) {
        _ = SetCursorPos(Int32(p.x.rounded()), Int32(p.y.rounded()))
    }

    // track delivers the hook's moves and button releases to moved until it is nil.
    func track(_ moved: (() -> Void)?) {
        self.moved = moved
    }
}
