import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeChain saves two chains bound to Ctrl+Alt+Shift+1 and Ctrl+Alt+Shift+2, neither in the
// default keymap nor owned by the shell: Halves loops left-half then first-third, Once runs the same
// steps without looping. It binds the hotkeys, and for each chain puts the front window at
// 200,150,500,350, injects the chord three times and prints the frame after each press. Repeat
// cycling is off so a repeated step stays where it is.
func probeChain(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("chain: no window of \(opts.app)")
        return 1
    }
    let steps = ["left-half", "first-third"]
    let halves = Chain(name: "Halves", steps: steps, loops: true)
    let once = Chain(name: "Once", steps: steps, loops: false)
    var choices = Choices()
    choices.behavior.subsequentExecution = SubsequentExecution.none
    choices.chains = [halves, once]
    choices.shortcuts[halves.actionName] = StoredShortcut(mods: ["ctrl", "alt", "shift"], key: "1")
    choices.shortcuts[once.actionName] = StoredShortcut(mods: ["ctrl", "alt", "shift"], key: "2")
    let store = Store()
    do {
        try store.save(choices)
    } catch {
        print("chain: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    app.hotkeys.bind(Bindings(app.engine.anchors.choices).map, runnable: app.engine.actions.supports)
    defer { app.hotkeys.unbind() }
    let bound = Set(app.hotkeys.names.values)
    var ran = true
    let start = Frame(x: 200, y: 150, w: 500, h: 350)
    let reset = {
        app.windows.move(pad.id, to: start)
        _ = bringForward(hwnd)
        app.run(until: App.now + 0.6)
    }
    reset()
    if let w = WinWindows.scan(screens: screens).windows.first(where: { $0.id == pad.id }) {
        for name in steps {
            let label = name == "first-third" ? "left-third" : name
            print("\(label): \(app.engine.actions.preview(name, for: w, screens: screens).map(pixels) ?? "none")")
        }
    }
    for (chain, key) in [(halves, WORD(0x31)), (once, WORD(0x32))] {
        print("bound \(chain.actionName): \(bound.contains(chain.actionName))")
        reset()
        for k in 1...3 {
            _ = press([0x11, 0x12, 0x10, key])
            app.run(until: App.now + 0.6)
            let frame = app.windows.frame(pad.id).map(pixels)
            ran = ran && frame != nil
            print("\(chain.name) press \(k): \(frame ?? "gone")")
        }
    }
    return ran ? 0 : 1
}
