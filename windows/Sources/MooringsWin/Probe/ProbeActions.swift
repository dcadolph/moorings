import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeActions binds the whole default keymap, then runs every action in it and in the Window
// folder's families once from a fixed start frame on the front window of the app, and prints the
// frame the engine's preview wanted beside the frame the window ended at. Routed actions have no
// Windows hook yet and are listed without running. The actions that minimize or close come last,
// and the window is restored after each minimize, so every action starts from the same frame.
func probeActions(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("actions: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("actions: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let map = Bindings(app.engine.anchors.choices).map
    app.hotkeys.bind(map, runnable: app.engine.actions.supports)
    defer { app.hotkeys.unbind() }
    print("table: \(map.count) registered: \(app.hotkeys.names.count) skipped: \(app.hotkeys.skipped.count)")
    for s in app.hotkeys.skipped {
        print("skipped \(s.name): \(s.reason) routed \(app.engine.actions.routed(s.name))")
    }
    let last = ["minimize-others", "close-others", "minimize-window", "close-window"]
    let window = ActionRunner.families.flatMap { $0.names + $0.groups.flatMap(\.names) }
    let names = Set(map.keys).union(window).sorted()
    let ordered = names.filter { !last.contains($0) } + last.filter { names.contains($0) }
    let start = Frame(x: 200, y: 150, w: 500, h: 350)
    app.windows.move(pad.id, to: Frame(x: start.x, y: start.y, w: 1, h: 1))
    app.run(until: App.now + 0.3)
    guard let least = app.windows.frame(pad.id) else {
        print("actions: window gone")
        return 1
    }
    print("minimum: \(Int(least.w)) \(Int(least.h))")
    var compared = 0, bare = 0
    var worst = 0
    for name in ordered {
        if app.engine.actions.routed(name) {
            print("action \(name): routed, later unit")
            continue
        }
        if IsIconic(hwnd) {
            _ = ShowWindow(hwnd, 9)
        }
        app.windows.move(pad.id, to: start)
        _ = bringForward(hwnd)
        app.run(until: App.now + 0.2)
        let scan = app.windows.scan(screens, full: true).windows
        let want = scan.first(where: { $0.id == pad.id }).flatMap {
            app.engine.actions.preview(name, for: $0, screens: screens)
        }
        let ran = app.engine.actions.run(name, window: pad.id)
        app.run(until: App.now + 0.3)
        let got = app.windows.frame(pad.id)
        if let want, let got {
            let (dx, dw) = actionAxis(want.x, want.w, got.x, got.w, least: least.w)
            let (dy, dh) = actionAxis(want.y, want.h, got.y, got.h, least: least.h)
            let off = Int(max(dx, dy, dw, dh).rounded())
            worst = max(worst, off)
            compared += 1
            let kept = want.w < least.w - 1 || want.h < least.h - 1 ? " kept a minimum" : ""
            print("action \(name): want \(pixels(want)) got \(pixels(got))\(kept) off \(off)")
        } else {
            bare += 1
            let why = want != nil ? "window gone" : got == nil ? "window gone" : "none on this scene"
            print("action \(name): no frame ran \(ran) \(why)")
        }
    }
    print("actions: \(compared) compared, \(bare) without a frame, worst off \(worst)")
    return 0
}

// actionAxis returns how far one axis of a landed frame is off the wanted one. When the wanted
// length is under the app's least length, the window keeps that least length and its near edge
// may shift back by the difference to stay on the screen, so either edge in that range is on.
func actionAxis(_ want: Double, _ wantLen: Double, _ got: Double, _ gotLen: Double, least: Double)
    -> (Double, Double)
{
    guard wantLen < least - 1 else {
        return (abs(want - got), abs(wantLen - gotLen))
    }
    let slack = least - wantLen
    let edge = got > want ? got - want : got < want - slack ? want - slack - got : 0
    return (edge, abs(least - gotLen))
}
