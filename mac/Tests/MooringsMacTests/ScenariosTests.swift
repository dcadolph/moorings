import AppKit
import ApplicationServices
import Foundation
import Testing

import MooringsCore
import MooringsEngine
import MooringsTesting

@testable import Moorings

// MacHost places a window through the store, which is outside the engine's own moves, drags one with
// posted mouse events, and takes no picture: a screen capture on the owner's Mac waits for the owner's
// word.
extension MacHost: @preconcurrency ScenarioHost {
    // place moves the window with id to frame through Accessibility, as another app would.
    func place(_ id: WindowID, at frame: Frame) -> Bool {
        guard store.frame(id) != nil else { return false }
        store.move(id, to: frame, from: nil, behavior: Behaviors())
        return true
    }

    // drag raises the window, presses on its title bar with a posted event, moves the pointer by
    // offset in 20 steps 15 ms apart with held down and lets go, and feeds drag each point the way
    // the app's event tap feeds MacDrag, since a test host runs no tap.
    func drag(_ id: WindowID, by offset: Point, held: Modifiers) -> Bool {
        guard let drag, let f = store.frame(id) else { return false }
        store.raise(id)
        let grab = Scenarios.grab(f)
        let flags = CGEventFlags(
            rawValue: Modifiers.sideFree.filter { held.contains($0.0) }.reduce(0) { $0 | $1.1 })
        func post(_ type: CGEventType, _ p: Point) {
            let e = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y),
                mouseButton: .left)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown, grab)
        drag.began(at: grab)
        _ = wait(until: now + 0.1) { false }
        for i in 1...20 {
            let p = Point(x: grab.x + offset.x * Double(i) / 20, y: grab.y + offset.y * Double(i) / 20)
            post(.leftMouseDragged, p)
            _ = wait(until: now + 0.015) { false }
            drag.moved(p, held: held)
        }
        _ = wait(until: now + 0.2) { false }
        post(.leftMouseUp, Point(x: grab.x + offset.x, y: grab.y + offset.y))
        drag.ended(held: [])
        return true
    }
}

// The Mac engine shows every scenario's behavior on TextEdit windows. Without Accessibility access the
// test prints why and passes; it runs live on the owner's go.
@Test @MainActor func testMacScenarios() {
    guard AXIsProcessTrusted() else {
        print("Mac scenarios skipped: this test host has no Accessibility access")
        return
    }
    _ = NSApplication.shared
    let store = Windows()
    let host = MacHost(store: store)
    let defaults = DefaultsStore(key: "moorings.scenarios.\(UUID().uuidString)") { _ in }
    defer {
        UserDefaults.standard.removeObject(forKey: defaults.key)
        UserDefaults.standard.removeObject(forKey: defaults.asideKey)
    }
    let banner = BannerPanel()
    let platform = Platform(
        windows: store, screens: MacScreens(), overlay: Footprint(),
        notifier: MacNotifier { banner.show($0, $1, palette: .harbor) }, clock: MacClock(), store: defaults,
        pointer: MacPointer(), keys: MacKeys(Hotkeys { _ in }), apps: MacApps(), log: MacLog(), timers: MacTimers(),
        events: MacEvents(store: store), grid: GridPanel(), badge: BadgePanel())
    let engine = Engine(platform: platform, features: .all)
    host.drag = engine.drag
    let report = ScenarioReport(host: "mac", results: Scenarios.run(engine, host: host))
    for r in report.results {
        print("scenario \(r.name): \(r.notes.joined(separator: "; "))")
    }
    print("Mac \(report.summary)")
    #expect(report.failures.isEmpty, "\(report.failures)")
}
