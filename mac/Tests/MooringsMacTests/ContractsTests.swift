import AppKit
import ApplicationServices
import Foundation
import Testing

import MooringsCore
import MooringsEngine
import MooringsTesting

@testable import Moorings

// MacHost is the Mac ContractHost: each window is a Probe window, and waiting runs the main run loop.
@MainActor
final class MacHost: @preconcurrency ContractHost {
    // probe is the probe's bundle id. make probe in mac/ builds and registers it.
    static let probe = Selftest.bundle
    // store reads the windows the host opens.
    let store: Windows
    // opened lists the windows the host opened.
    private var opened: [WindowID] = []
    // defaults is the store spoilChoices writes under, nil when the host spoils none.
    var defaults: DefaultsStore?
    // drag is the follower the host's drags feed, nil when the host drags nothing.
    var drag: DragFollower?

    // init builds a host whose windows store reads.
    init(store: Windows) {
        self.store = store
    }

    // minimum is the smallest frame the probe's windows take.
    var minimum: (w: Double, h: Double)? { (240, 160) }

    // now is the system uptime in seconds, the clock the Mac adapters use.
    var now: Double { ProcessInfo.processInfo.systemUptime }

    // screens reads the attached screens.
    func screens() -> Screens {
        Screens.current()
    }

    // open asks the probe for a window, launching it when it is not running, and returns the window
    // once it shows.
    func open() -> WindowID? {
        let before = Set(store.scan(screens(), full: true).windows.map(\.id))
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.probe).first {
            running.activate()
            DistributedNotificationCenter.default().postNotificationName(
                Selftest.newWindow, object: nil, userInfo: nil, deliverImmediately: true)
        } else {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.probe) else { return nil }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: app, configuration: config, completionHandler: nil)
        }
        var found: WindowID?
        _ = wait(until: now + 10) {
            found =
                store.scan(screens(), full: true).windows.first {
                    $0.bundle == Self.probe && !before.contains($0.id)
                }?.id
            return found != nil
        }
        if let found {
            opened.append(found)
        }
        return found
    }

    // openRefusing is nil: no stock app's window refuses every Accessibility move.
    func openRefusing() -> WindowID? {
        nil
    }

    // knownApp is the probe, the app the host opens its windows in.
    var knownApp: String? { Self.probe }

    // nudge moves the window with id 8 points right and down through the store, which posts the
    // window's moved notification as a drag would.
    func nudge(_ id: WindowID) -> Bool {
        guard let f = store.frame(id) else { return false }
        store.position(id, x: f.x + 8, y: f.y + 8)
        return true
    }

    // wait runs the main run loop in 10 ms turns until done or the deadline.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        while !done() {
            guard now < deadline else { return false }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        return true
    }

    // finish closes every window the host opened.
    func finish() {
        _ = store.scan(screens(), full: true)
        for id in opened {
            store.close(id)
        }
        opened = []
    }

    // spoilChoices writes payload under the defaults store's key, when the host has one.
    func spoilChoices(_ payload: Data) -> Bool {
        guard let defaults else { return false }
        UserDefaults.standard.set(payload, forKey: defaults.key)
        return true
    }

    // choicesAside reads what the defaults store moved aside, when the host has one.
    func choicesAside() -> Data? {
        defaults.flatMap { UserDefaults.standard.data(forKey: $0.asideKey) }
    }
}

// The Mac adapters keep every contract rule. The suite opens and moves real Probe windows, so it
// runs only when MOORINGS_LIVE_CONTRACTS is 1: on GitHub's macOS runner, and locally on the owner's
// go. Otherwise, or without Accessibility access, it is skipped.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MOORINGS_LIVE_CONTRACTS"] == "1",
        "MOORINGS_LIVE_CONTRACTS is not 1"),
    .enabled(if: AXIsProcessTrusted(), "this test host has no Accessibility access")
) @MainActor func testMacContracts() {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: MacHost.probe) != nil else {
        Issue.record("the probe is not installed. Run make probe in mac/ first")
        return
    }
    _ = NSApplication.shared
    let store = Windows()
    let host = MacHost(store: store)
    let banner = BannerPanel()
    var failures = WindowStoreContract.run(store, host: host)
    failures += OverlayContract.run(Footprint(), store: store, host: host)
    failures += BadgeContract.run(BadgePanel(), store: store, host: host)
    failures += GridContract.run(GridPanel(), store: store, host: host)
    failures += NotifierContract.run(MacNotifier { banner.show($0, $1, palette: .harbor) }, store: store, host: host)
    failures += SchedulerContract.run(MacScheduler(), clock: MacClock(), host: host)
    failures += PointerContract.run(MacPointer(), host: host)
    var delivered: [String] = []
    failures += KeysContract.run(MacKeys(Hotkeys { delivered.append($0) }), host: host, actions: { delivered })
    failures += LogContract.run(MacLog(), host: host)
    failures += TimersContract.run(MacTimers(), clock: MacClock(), host: host)
    failures += EventSourceContract.run(MacEvents(store: store), store: store, host: host)
    failures += ScreenSourceContract.run(MacScreens(), host: host)
    failures += ClockContract.run(MacClock(), host: host)
    failures += AppsContract.run(MacApps(), store: store, host: host)
    print("Mac contracts: 14 suites, \(failures.count) failures")
    #expect(failures.isEmpty, "\(failures)")
}

// The Mac adapters that need no Accessibility and open no window keep their rules: the log, the
// timers, the choices under a throwaway defaults key, and the apps' refusal of a bundle that does not
// exist.
@Test @MainActor func testMacPureAdapters() {
    let host = MacHost(store: Windows())
    var failures = LogContract.run(MacLog(), host: host)
    failures += TimersContract.run(MacTimers(), clock: MacClock(), host: host)
    let defaults = DefaultsStore(key: "moorings.contract.\(UUID().uuidString)") { _ in }
    host.defaults = defaults
    failures += ChoicesStoreContract.run(defaults, host: host)
    UserDefaults.standard.removeObject(forKey: defaults.key)
    UserDefaults.standard.removeObject(forKey: defaults.asideKey)
    #expect(failures.isEmpty, "\(failures)")
    #expect(!MacApps().open("com.example.moorings.no-such-app", background: true, target: nil))
    #expect(MacLog.name(.passes) == "anchors")
    #expect(MacLog.name(.choices) == "choices")
}
