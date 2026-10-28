import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeEvents runs the pass loop with no anchored app for the given seconds, and prints each
// window event that woke it, each pass, and the counts of events hooked and kept.
func probeEvents(_ opts: ProbeOptions) -> Int32 {
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("events: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    app.events.filters = !opts.noFilter
    var kept = 0, passes = 0
    print("start at \(stamp(App.now))")
    app.engine.observers.noticed = { event, t in
        kept += 1
        print("event \(eventName(event)) at \(stamp(t))")
    }
    app.engine.observers.passed = { t, moves in
        passes += 1
        print("pass at \(stamp(t)) moves \(moves)")
    }
    app.run(until: App.now + opts.seconds)
    print("raw events: \(app.events.raw) passed: \(app.events.passed) kept: \(kept) passes: \(passes)")
    return 0
}

// eventName names a window event the way the events probe prints it: its kind, then the window in
// hex or the app.
func eventName(_ event: WindowEvent) -> String {
    switch event {
    case let .moved(id): "moved \(hex(id))"
    case let .shown(id): "shown \(hex(id))"
    case let .destroyed(id): "destroyed \(hex(id))"
    case let .focused(id): "focused \(hex(id))"
    case let .appLaunched(app): "appLaunched \(app)"
    case let .appQuit(app): "appQuit \(app)"
    case .screensChanged: "screensChanged"
    case .wake: "wake"
    }
}
