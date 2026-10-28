import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeMoor pins the front Notepad to the left top slot in a fresh choices file with slot stacks
// off, so a second Notepad is kept in the channel, runs the pass loop for the given seconds, and
// prints each move and release with its time, then the final frames.
func probeMoor(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("moor: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("moor: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    var choices = Choices(
        slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30),
        paused: opts.paused)
    choices.slotStacks = false
    do {
        try store.save(choices)
    } catch {
        print("moor: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    print("start at \(stamp(App.now)) pinned \(hex(pad.id)) paused \(app.engine.anchors.choices.paused)")
    app.engine.observers.moved = { move, t, got in
        print(
            "move \(hex(move.id)) at \(stamp(t)) to \(pixels(move.frame))",
            "got \(got.map(pixels) ?? "gone")")
    }
    app.engine.observers.released = { id, t in print("released \(hex(id)) at \(stamp(t))") }
    app.notify = { title, body in print("notice: \(title): \(body)") }
    app.run(until: App.now + opts.seconds)
    let use = app.engine.anchors.inUse(wide)
    print("strip: \(pixels(Geometry.regions(wide, use.left, use.right).left))")
    print("channel: \(pixels(app.engine.anchors.channel(wide)))")
    for w in WinWindows.scan(screens: screens).windows {
        print(
            "final \(hex(w.id)) pid \(WinWindows.hwnd(w.id).map(WinWindows.processID) ?? 0)",
            "frame \(pixels(w.frame))")
    }
    return 0
}
