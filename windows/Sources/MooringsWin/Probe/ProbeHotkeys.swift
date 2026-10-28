import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// heldChord is Ctrl+Alt+Left, Left half in the built-in keymaps: the chord the hotkeys probe injects
// and the hold probe takes first.
let heldChord = (mods: UINT(0x0002 | 0x0001), vk: UINT(0x25))

// probeHotkeys binds the shortcuts from a fresh choices file, prints what was registered and
// skipped, brings the front Notepad forward, injects Ctrl+Alt+Left, runs the loop for the given
// seconds, and prints the presses received, Notepad's frame and the channel.
func probeHotkeys(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("hotkeys: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("hotkeys: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("hotkeys: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let map = Bindings(app.engine.anchors.choices).map
    app.hotkeys.bind(map, runnable: app.engine.actions.supports)
    defer { app.hotkeys.unbind() }
    print("table: \(map.count) registered: \(app.hotkeys.names.count) skipped: \(app.hotkeys.skipped.count)")
    for s in app.hotkeys.skipped {
        print("skipped \(s.name): \(s.reason)")
    }
    print("foreground before: \(foreground())")
    _ = bringForward(hwnd)
    print("foreground after: \(foreground()) notepad \(hex(pad.id))")
    print("before: \(pixels(pad.frame))")
    print("sent: \(press([0x11, 0x12, 0x25]))")
    app.run(until: App.now + opts.seconds)
    let pressed = app.hotkeys.pressed
    print("hotkeys received: \(pressed.isEmpty ? "none" : pressed.joined(separator: ","))")
    print("after: \(app.windows.frame(pad.id).map(pixels) ?? "gone")")
    print("channel: \(pixels(app.engine.anchors.channel(wide)))")
    return 0
}
