import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// cycleChord is Ctrl+Alt+Shift+P, the shortcut the organize probe binds cycle-stacked-windows to.
let cycleChord = StoredShortcut(mods: ["ctrl", "alt", "shift"], key: "p")

// probeOrganize staggers every window of the app on a fresh choices file, paused under --paused, and
// runs the organize actions through the action runner from the first of them: tile-columns, tile-rows,
// cascade-all, then cycle-stacked-windows on the windows stacked 5 px apart by pressing its bound
// shortcut, since only a process that took the last input may raise another app's window, then
// reverse-all, fit-channel, Tidy 2 and Undo tidy. It prints the area, the free windows the actions
// share it with, how many fit cells the area holds, and each window's frame after each action, so the
// workflow judges the app's windows and not the others, which may keep their own minimum size.
func probeOrganize(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let store = Store()
    var choices = Choices(paused: opts.paused)
    choices.shortcuts["cycle-stacked-windows"] = cycleChord
    do {
        try store.save(choices)
    } catch {
        print("organize: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let pads = app.windows.scan(screens, full: true).windows.filter { $0.bundle.hasSuffix(opts.app) }
    guard let first = pads.first, let i = screens.index(first.frame) else {
        print("organize: no window of \(opts.app)")
        return 1
    }
    let area = app.engine.organizer.area(screens, i)
    let ids = Set(pads.map(\.id))
    let settle = { app.run(until: App.now + 0.5) }
    let show = { (label: String) in
        for p in pads {
            print("\(label) \(hex(p.id)): \(app.windows.frame(p.id).map(pixels) ?? "gone")")
        }
    }
    let front = { WinWindows.scan(screens: screens).windows.first { ids.contains($0.id) }?.id }
    let stack = { (gap: Double) in
        for (k, p) in pads.enumerated() {
            let f = Frame(x: area.x + 100 + gap * Double(k), y: area.y + 100 + gap * Double(k), w: 500, h: 350)
            app.windows.move(p.id, to: f, from: nil, behavior: Behaviors())
            if let hwnd = WinWindows.hwnd(p.id) {
                bringForward(hwnd)
            }
        }
        settle()
    }
    stack(40)
    let free = app.windows.scan(screens, full: true).windows.filter {
        !app.engine.anchors.pinned($0) && !$0.isFullScreen && screens.index($0.frame) == i
    }
    print("pads: \(pads.count)")
    print("free: \(free.count)")
    print("area: \(pixels(area))")
    print("fit capacity: \(Tile.fitCapacity(area))")
    print("paused: \(app.engine.anchors.choices.paused)")
    show("start")
    for name in ["tile-columns", "tile-rows", "cascade-all", "cycle-stacked-windows", "reverse-all", "fit-channel"] {
        guard name == "cycle-stacked-windows" else {
            let ran = app.engine.actions.run(name, window: first.id)
            settle()
            print("\(name): ran \(ran)")
            show(name)
            continue
        }
        stack(5)
        show("stacked")
        print("front before: \(front().map(hex) ?? "none")")
        let map = Bindings(app.engine.anchors.choices).map
        app.hotkeys.bind(map, runnable: app.engine.actions.supports)
        print("cycle bound: \(app.hotkeys.names.values.contains(name))")
        print("sent: \(press([0x11, 0x12, 0x10, 0x50]))")
        settle()
        app.hotkeys.unbind()
        print("\(name): pressed \(app.hotkeys.pressed.contains(name))")
        print("front after: \(front().map(hex) ?? "none")")
        show(name)
    }
    if let hwnd = WinWindows.hwnd(first.id) {
        bringForward(hwnd)
    }
    app.engine.organizer.tidy(2)
    settle()
    show("tidy-2")
    app.engine.organizer.undo()
    settle()
    show("undo")
    return 0
}

// probeBadge stacks every window of the app 5 px apart with the last one raised, on a fresh choices
// file with the stack badge on, or off under --no-badge. It rests the pointer 10 px inside the front
// window's corner for three ticks and prints the badge's mark and its window's rect, then moves the
// pointer 40 px and prints them again. The front window is read from the z order, since the foreground
// lock can refuse the last raise.
func probeBadge(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    var choices = Choices()
    choices.stacking.badge = !opts.noBadge
    let store = Store()
    do {
        try store.save(choices)
    } catch {
        print("badge: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let pads = app.windows.scan(screens, full: true).windows.filter { $0.bundle.hasSuffix(opts.app) }
    guard let at = pads.first.flatMap({ screens.index($0.frame) }) else {
        print("badge: no window of \(opts.app)")
        return 1
    }
    let area = app.engine.organizer.area(screens, at)
    for (k, p) in pads.enumerated() {
        let f = Frame(x: area.x + 100 + 5 * Double(k), y: area.y + 100 + 5 * Double(k), w: 500, h: 350)
        app.windows.move(p.id, to: f, from: nil, behavior: Behaviors())
        if let hwnd = WinWindows.hwnd(p.id) {
            bringForward(hwnd)
        }
        app.run(until: App.now + 0.2)
    }
    let ids = Set(pads.map(\.id))
    guard let front = WinWindows.scan(screens: screens).windows.first(where: { ids.contains($0.id) })?.frame else {
        print("badge: no window of \(opts.app) in the z order")
        return 1
    }
    print("pads: \(pads.count)")
    print("front: \(pixels(front))")
    app.engine.badge.sync()
    print("ticking: \(app.engine.badge.running)")
    let report = { (label: String) in
        print("\(label): \(app.badge.shown.map { "\($0.count) at \(pixels($0.front))" } ?? "none")")
        guard let hwnd = app.badge.window else {
            print("\(label) window: none")
            return
        }
        var r = RECT()
        _ = GetWindowRect(hwnd, &r)
        let scale = Double(GetDpiForWindow(hwnd)) / 96
        print(
            "\(label) window: \(r.left) \(r.top) \(r.right - r.left) \(r.bottom - r.top) visible \(IsWindowVisible(hwnd)) "
                + "scale \(scale)")
    }
    let ticks = 3 * Pace.pollSeconds + 0.1
    _ = SetCursorPos(Int32(front.x + 10), Int32(front.y + 10))
    app.run(until: App.now + ticks)
    report("rest")
    _ = SetCursorPos(Int32(front.x + 50), Int32(front.y + 50))
    app.run(until: App.now + ticks)
    report("away")
    app.badge.hide()
    return 0
}
