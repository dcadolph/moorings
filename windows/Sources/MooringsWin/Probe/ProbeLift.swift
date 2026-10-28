import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeLift pins the front Notepad to the left top slot, lets the loop place it, then runs Maximize
// on it twice, the way Ctrl+Alt+Enter does, and prints its frame after each.
func probeLift(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("lift: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("lift: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30)))
    } catch {
        print("lift: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let frame = { app.windows.frame(pad.id).map(pixels) ?? "gone" }
    app.run(until: App.now + 1.5)
    print("placed: \(frame())")
    _ = bringForward(hwnd)
    print("foreground: \(foreground()) notepad \(hex(pad.id))")
    print("lift ran: \(app.engine.actions.run("maximize")) lifted \(app.engine.anchors.isLifted(pad.id))")
    app.run(until: App.now + 1.5)
    print("lifted: \(frame())")
    print("lower ran: \(app.engine.actions.run("maximize")) lifted \(app.engine.anchors.isLifted(pad.id))")
    app.run(until: App.now + 1.5)
    print("lowered: \(frame())")
    let use = app.engine.anchors.inUse(wide)
    print("strip: \(pixels(Geometry.regions(wide, use.left, use.right).left))")
    print("over: \(pixels(Geometry.lift(wide, .left, use.left, use.right)))")
    return 0
}
