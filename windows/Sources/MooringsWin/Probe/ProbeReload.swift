import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeReload pins the front Notepad in left top, then changes the choices file twice. The control
// writes a narrower left width with the file's old write time restored, which no pass may notice.
// The real write gets a new write time, which the next pass reloads. It prints the frame at each
// step, the reload count, and the strip the core computes for the new choices.
func probeReload(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("reload: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("reload: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    let narrow = Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 30, right: 30))
    do {
        try store.save(Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30)))
    } catch {
        print("reload: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    var reloads = 0
    app.log.heard = { category, line in
        if category == .choices && line == "choices reloaded" {
            reloads += 1
        }
    }
    let frame = { app.windows.frame(pad.id).map(pixels) ?? "gone" }
    app.run(until: App.now + 1.5)
    print("before: \(frame())")
    guard let old = store.writeTime() else {
        print("reload: no write time")
        return 1
    }
    do {
        try Choices.encode(narrow).write(to: store.url)
    } catch {
        print("reload: \(error)")
        return 1
    }
    guard store.setWriteTime(old) else {
        print("reload: write time not restored")
        return 1
    }
    app.engine.wake()
    app.run(until: App.now + 1.5)
    print("control: \(frame()) reloads \(reloads)")
    do {
        try Choices.encode(narrow).write(to: store.url)
    } catch {
        print("reload: \(error)")
        return 1
    }
    app.engine.wake()
    app.run(until: App.now + 1.5)
    print("after: \(frame()) reloads \(reloads)")
    let use = app.engine.anchors.inUse(wide)
    print("strip: \(pixels(Geometry.regions(wide, use.left, use.right).left))")
    return 0
}
