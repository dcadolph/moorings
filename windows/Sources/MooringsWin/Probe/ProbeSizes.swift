import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeSizes saves two custom sizes with a 12 pixel gap, Quarter in shares of the area from its top
// left corner and Note in points, and prints the Custom sizes folder the tray builds from them. It
// runs each size through the tray's command on the front window of the app and prints the engine's
// preview beside the read-back, then runs Quarter again with no gap, the control, since the gap moves
// Quarter's left and top edges by the whole gap.
func probeSizes(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    var choices = Choices()
    choices.sizes = [
        StoredSize(title: "Quarter", x: 0, y: 0, w: 0.5, h: 0.5),
        StoredSize(title: "Note", width: 400, height: 300),
    ]
    choices.gapPx = 12
    let store = Store()
    do {
        try store.save(choices)
    } catch {
        print("sizes: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    guard let pad = app.windows.scan(screens, full: true).windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("sizes: no window of \(opts.app)")
        return 1
    }
    let tray = Tray(app: app)
    if let folder = Tray.sizesFolder(choices: app.engine.anchors.choices) {
        printMenu([folder])
    }
    let names = Bindings(app.engine.anchors.choices).sizes.map(\.name)
    print("sizes: \(names.map(Keymaps.label).joined(separator: " "))")
    let start = Frame(x: 200, y: 150, w: 500, h: 350)
    let run = { (name: String, label: String) in
        app.windows.move(pad.id, to: start, from: nil, behavior: Behaviors())
        bringForward(hwnd)
        app.run(until: App.now + 0.3)
        let w = app.windows.scan(screens, full: true).windows.first { $0.id == pad.id }
        let want = w.flatMap { app.engine.actions.preview(name, for: $0, screens: screens) }
        tray.perform(.action(name))
        app.run(until: App.now + 0.3)
        let got = app.windows.frame(pad.id)
        print("\(label): want \(want.map(pixels) ?? "none") got \(got.map(pixels) ?? "none")")
    }
    for name in names {
        run(name, Keymaps.label(name))
    }
    if let first = names.first {
        app.engine.anchors.choices.gapPx = 0
        run(first, "nogap \(Keymaps.label(first))")
    }
    return 0
}
