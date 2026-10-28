import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// dragTarget is where the drag probe lets go: the left edge, below the corner zones.
let dragTarget = (x: Int32(2), y: Int32(400))

// probeDrag runs the pass loop with a fresh choices file while another thread presses on the front
// Notepad's caption with SendInput, drags it to the left edge in 20 steps and lets go, with Alt held
// through the drop for --alt. It prints the drop, Notepad's frame, the channel, the left top holder
// and how often the hook was put back.
func probeDrag(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("drag: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("drag: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("drag: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    app.hooksMouse = !opts.noHook
    app.engine.observers.dropped = { id, drop in
        let on =
            switch drop {
            case let .zone(name): "zone \(name)"
            case let .park(key): "park \(key)"
            case .none: "nothing"
            }
        print("dropped \(hex(id)) on \(on) at \(stamp(App.now))")
    }
    _ = bringForward(hwnd)
    print("before: \(pixels(pad.frame))")
    var full: WindowsBool = false
    _ = SystemParametersInfoW(UINT(SPI_GETDRAGFULLWINDOWS), 0, &full, 0)
    print("drag full windows: \(full.boolValue)")
    let from = (x: Int32((pad.frame.x + pad.frame.w / 2).rounded()), y: Int32(pad.frame.y + 15))
    let alt = opts.alt
    Thread {
        Sleep(1000)
        dragInput(from: from, to: dragTarget, keys: alt ? [0x12] : [])
    }.start()
    app.run(until: App.now + opts.seconds)
    print("hook delivered: \(WinMouseHook.delivered)")
    print("hook reinstalled: \(app.mouse.reinstalls)")
    print(
        "footprint: \(app.footprint.last.map(pixels) ?? "never") shows \(app.footprint.shows)",
        "hidden \(app.footprint.shown == nil)")
    print("after: \(app.windows.frame(pad.id).map(pixels) ?? "gone")")
    print("channel: \(pixels(app.engine.anchors.channel(wide)))")
    print("left top: \(app.engine.anchors.choices.slots[.leftTop] ?? "")")
    return 0
}
