import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeSkip pins the front Notepad to the left top slot, runs the pass loop for the given seconds,
// and prints the integrity of the probe and of each window's process, each move with its read-back,
// each notice, the windows refused as elevated, and the final frames. The workflow puts Task Manager
// and a packaged app on the left strip first.
func probeSkip(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("skip: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("skip: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    let choices = Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30))
    do {
        try store.save(choices)
    } catch {
        print("skip: \(error)")
        return 1
    }
    print("probe integrity: \(integrity(GetCurrentProcessId()))")
    for w in windows {
        let pid = WinWindows.hwnd(w.id).map(WinWindows.processID) ?? 0
        print("window \(hex(w.id)): \(w.bundle) frame \(pixels(w.frame)) integrity \(integrity(pid))")
    }
    let app = App(store: store, minAspect: opts.minAspect)
    print("start at \(stamp(App.now)) pinned \(hex(pad.id))")
    app.engine.observers.moved = { move, t, got in
        print(
            "move \(hex(move.id)) at \(stamp(t)) to \(pixels(move.frame))",
            "got \(got.map(pixels) ?? "gone")")
    }
    app.notify = { title, body in print("notice: \(title): \(body)") }
    app.run(until: App.now + opts.seconds)
    print("end at \(stamp(App.now))")
    for id in app.windows.elevated.sorted() {
        print("skipped \(hex(id)): elevated")
    }
    print("channel: \(pixels(app.engine.anchors.channel(wide)))")
    for w in WinWindows.scan(screens: screens).windows {
        print("final \(hex(w.id)) frame \(pixels(w.frame))")
    }
    return 0
}
