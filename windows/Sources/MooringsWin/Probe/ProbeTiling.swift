import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeTiling turns on tiling in columns through the tray's Tiling folder on a fresh choices file, or
// leaves it off under --no-tiling, the control, and prints the folder. It opens two stand-in windows
// stacked in the area, then a third, then closes the first, and after each step prints every open
// stand-in's frame beside the column of the layout it should hold, so the workflow judges the probe's
// own windows and not the others, which may keep their own minimum size. Under --no-tiling each want
// is the frame the probe placed the window at. It also prints each window's frame beside where it was
// placed, which tiling must have changed.
func probeTiling(_ opts: ProbeOptions) -> Int32 {
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-tiling-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: Store(url: file).aside)
    }
    let store = Store(url: file)
    do {
        try store.save(Choices())
    } catch {
        print("tiling: \(error)")
        return 1
    }
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let i = screens.host else {
        print("tiling: no host display at min aspect \(opts.minAspect)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let host = WinHost(minAspect: opts.minAspect)
    host.timers = { app.timers.fire($0) || app.mouse.tick($0) }
    defer { host.finish() }
    let tray = Tray(app: app)
    if !opts.noTiling {
        tray.perform(.action(Tiling.modePrefix + TileMode.columns.rawValue))
    }
    printMenu([Tray.tilingFolder(choices: app.engine.anchors.choices)])
    print("mode: \(app.engine.anchors.choices.tiling.mode.rawValue)")
    let area = app.engine.organizer.area(screens, i)
    print("area: \(pixels(area))")
    var placed: [WindowID: Frame] = [:]
    var pads: [WindowID] = []
    let open = { (k: Int) -> Bool in
        guard let id = host.open() else {
            print("tiling: stand-in \(k) did not open")
            return false
        }
        let f = Frame(x: area.x + 100 + 40 * Double(k), y: area.y + 100 + 40 * Double(k), w: 500, h: 350)
        app.windows.move(id, to: f, from: nil, behavior: Behaviors())
        placed[id] = f
        pads.append(id)
        return true
    }
    let show = { (label: String) in
        app.run(until: App.now + 1)
        let now = Screens.current(minAspect: opts.minAspect)
        let anchors = app.engine.anchors
        let n = app.windows.scan(now, full: true).windows.filter {
            !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0) && !anchors.stashed.contains($0.id)
                && now.index($0.frame) == i
        }.count
        let columns = Tiling.layout(.columns, area, n, ratio: anchors.choices.tiling.ratio, gap: anchors.choices.gapPx)
        print("\(label) free: \(n)")
        for id in pads {
            let got = app.windows.frame(id)
            let want =
                opts.noTiling
                ? placed[id]
                : got.flatMap { g in columns.min { off($0, g) < off($1, g) } }
            print("\(label) \(hex(id)): want \(want.map(pixels) ?? "none") got \(got.map(pixels) ?? "none")")
            print(
                "placed \(label) \(hex(id)): want \(placed[id].map(pixels) ?? "none") got \(got.map(pixels) ?? "none")")
        }
    }
    guard open(0), open(1) else { return 1 }
    show("two")
    guard open(2) else { return 1 }
    show("three")
    let gone = pads.removeFirst()
    app.windows.close(gone)
    show("closed")
    print("closed: \(hex(gone)) \(app.windows.frame(gone) == nil ? "gone" : "still open")")
    return 0
}

// off is the largest distance between matching edges of a and b.
private func off(_ a: Frame, _ b: Frame) -> Double {
    max(abs(a.x - b.x), abs(a.y - b.y), abs(a.x + a.w - b.x - b.w), abs(a.y + a.h - b.y - b.h))
}
