import AppKit
import ApplicationServices
import Foundation
import Testing

import MooringsCore
import MooringsEngine
import MooringsTesting

@testable import Moorings

// MacHost is the Mac ContractHost: each window is a TextEdit document opened from a throwaway file,
// and waiting runs the main run loop.
@MainActor
final class MacHost: @preconcurrency ContractHost {
    // textEdit is TextEdit's bundle id.
    static let textEdit = "com.apple.TextEdit"
    // store reads the windows the host opens.
    private let store: Windows
    // files lists the throwaway files the host opened.
    private var files: [URL] = []
    // opened lists the windows the host opened.
    private var opened: [WindowID] = []

    // init builds a host whose windows store reads.
    init(store: Windows) {
        self.store = store
    }

    // minimum is nil: Accessibility does not say how small a TextEdit window may get.
    var minimum: (w: Double, h: Double)? { nil }

    // now is the system uptime in seconds, the clock the Mac adapters use.
    var now: Double { ProcessInfo.processInfo.systemUptime }

    // screens reads the attached screens.
    func screens() -> Screens {
        Screens.current()
    }

    // open opens a throwaway text file in TextEdit and returns its window once it shows.
    func open() -> WindowID? {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.textEdit) else { return nil }
        let before = Set(store.scan(screens(), full: true).windows.map(\.id))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moorings-contract-\(UUID().uuidString).txt")
        guard (try? Data("Moorings contract window.\n".utf8).write(to: url)) != nil else { return nil }
        files.append(url)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config, completionHandler: nil)
        var found: WindowID?
        _ = wait(until: now + 10) {
            found = store.scan(screens(), full: true).windows.first {
                $0.bundle == Self.textEdit && !before.contains($0.id)
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

    // wait runs the main run loop in 10 ms turns until done or the deadline.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        while !done() {
            guard now < deadline else { return false }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        return true
    }

    // finish closes every window the host opened and removes the throwaway files.
    func finish() {
        _ = store.scan(screens(), full: true)
        for id in opened {
            store.close(id)
        }
        opened = []
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
        files = []
    }
}

// The Mac adapters keep every contract rule. Without Accessibility access the suite prints why and
// passes; GitHub's macOS runner and a trusted local shell both run it live.
@Test @MainActor func testMacContracts() {
    guard AXIsProcessTrusted() else {
        print("Mac contracts skipped: this test host has no Accessibility access")
        return
    }
    _ = NSApplication.shared
    let store = Windows()
    let host = MacHost(store: store)
    let banner = BannerPanel()
    var failures = WindowStoreContract.run(store, host: host)
    failures += OverlayContract.run(Footprint(), store: store, host: host)
    failures += BadgeContract.run(BadgePanel(), store: store, host: host)
    failures += NotifierContract.run(MacNotifier { banner.show($0, $1, palette: .harbor) }, store: store, host: host)
    failures += SchedulerContract.run(MacScheduler(), clock: MacClock(), host: host)
    print("Mac contracts: 5 suites, \(failures.count) failures")
    #expect(failures.isEmpty, "\(failures)")
}
