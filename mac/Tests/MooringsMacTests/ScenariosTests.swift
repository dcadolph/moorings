import AppKit
import ApplicationServices
import Foundation
import Testing

import MooringsCore
import MooringsEngine
import MooringsTesting

@testable import Moorings

// MacHost places a window through the store, which is outside the engine's own moves, and takes no
// picture: a screen capture on the owner's Mac waits for the owner's word.
extension MacHost: @preconcurrency ScenarioHost {
    // place moves the window with id to frame through Accessibility, as another app would.
    func place(_ id: WindowID, at frame: Frame) -> Bool {
        guard store.frame(id) != nil else { return false }
        store.move(id, to: frame, from: nil, behavior: Behaviors())
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
    let report = ScenarioReport(host: "mac", results: Scenarios.run(engine, host: host))
    for r in report.results {
        print("scenario \(r.name): \(r.notes.joined(separator: "; "))")
    }
    print("Mac \(report.summary)")
    #expect(report.failures.isEmpty, "\(report.failures)")
}
