import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// liftedID is the window the host probe marks lifted, which a re-moor forgets.
private let liftedID: WindowID = 7

// probeHost shows a tray on a fake 1024x768 monitor, changes the monitor, and sends the tray window
// the messages Windows sends, printing the host key after each. The host follows a display change
// and a work area change, and any other setting change leaves it alone. A lifted mark shows whether
// the anchors were told to place everything again.
func probeHost(_ opts: ProbeOptions) -> Int32 {
    guard let small = Size("1024x768"), let large = Size("2560x1440"), let huge = Size("3440x1440") else {
        print("host: bad size")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("host: \(error)")
        return 1
    }
    Monitor.fake = .sized(small)
    let app = App(store: store)
    let tray = Tray(app: app)
    print("added: \(tray.show())")
    defer { tray.hide() }
    guard let window = tray.window else {
        print("host: no tray window")
        return 1
    }
    print("start: \(app.lastHost)")
    print("same: \(app.displaysChanged())")
    let anchors = app.engine.anchors
    anchors.toggleLift(id: liftedID)
    Monitor.fake = .sized(large)
    _ = SendMessageW(window, UINT(WM_WININICHANGE), 0, 0)
    print("other setting: \(app.lastHost) lifted \(anchors.isLifted(liftedID))")
    _ = SendMessageW(window, UINT(WM_WININICHANGE), WPARAM(SPI_SETWORKAREA), 0)
    print("work area: \(app.lastHost) lifted \(anchors.isLifted(liftedID))")
    Monitor.fake = .sized(large, scale: 2)
    _ = SendMessageW(window, UINT(WM_DISPLAYCHANGE), 0, 0)
    print("scale: \(app.lastHost)")
    Monitor.fake = .sized(huge)
    _ = SendMessageW(window, UINT(WM_DISPLAYCHANGE), 0, 0)
    print("ultrawide: \(app.lastHost)")
    return 0
}
