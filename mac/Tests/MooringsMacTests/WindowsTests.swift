import AppKit
import Foundation
import Testing

import MooringsCore

@testable import Moorings

// A window counts as alive while it is on screen or its element still answers, so a closed window
// the window server keeps listing drops out while one minimized or on another Space stays.
@Test func testLivingDropsDestroyedOffscreenWindows() {
    let tests: [(listed: [WindowID: Bool], destroyed: Set<WindowID>, want: Set<WindowID>)] = [
        // Test 0: Nothing listed.
        ([:], [], []),
        // Test 1: On screen and off screen, none destroyed.
        ([1: true, 2: false], [], [1, 2]),
        // Test 2: A closed window off screen drops out.
        ([1: true, 2: false], [2], [1]),
        // Test 3: An on-screen window stays even when its element reads as destroyed.
        ([1: true], [1], [1]),
        // Test 4: Every off-screen window closed.
        ([1: false, 2: false, 3: true], [1, 2], [3]),
    ]
    for (i, test) in tests.enumerated() {
        let got = Windows.living(test.listed) { test.destroyed.contains($0) }
        #expect(got == test.want, "test \(i)")
    }
}

// A scan right after an action's own move carries the last window server list instead of asking for
// a new one, and a scan after any app's event, a forced scan or one with nothing placed asks again.
@MainActor
@Test func testScanCarriesTheListAfterAnActionsMove() {
    var asked = 0
    let moved = Frame(x: 200, y: 0, w: 100, h: 100)
    let windows = Windows {
        asked += 1
        return [(id: 1, pid: 999_999, frame: Frame(x: 0, y: 0, w: 100, h: 100))]
    }
    let screens = Screens.current()
    _ = windows.scan(screens, full: false)
    #expect(asked == 1)
    // Test 0: An action placed window 1 and no app sent an event, so the scan carries the list.
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime, nil)
    _ = windows.scan(screens, full: false)
    #expect(asked == 1)
    // Test 1: Nothing placed since the last scan, so the scan asks.
    _ = windows.scan(screens, full: false)
    #expect(asked == 2)
    // Test 2: A placement and an app's event since the last scan, so the scan asks.
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime, nil)
    windows.appWoke[999_999] = ProcessInfo.processInfo.systemUptime
    _ = windows.scan(screens, full: false)
    #expect(asked == 3)
    // Test 3: A forced scan asks even right after a placement.
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime, nil)
    _ = windows.scan(screens, full: true)
    #expect(asked == 4)
}

// Asking the window server for one window gives what the full list shows for it, and nothing for a
// window it does not list.
@MainActor @Test func testOnScreenOneMatchesList() {
    for w in Windows.onScreen() {
        let got = Windows.onScreen(w.id)
        #expect(got?.pid == w.pid && got?.frame == w.frame, "window \(w.id)")
    }
    #expect(Windows.onScreen(WindowID(UInt32.max)) == nil)
}

// A press over a stalled app's window is named from the window server list without asking the app,
// and the stall lapses after stallSeconds so the app is asked again.
@MainActor @Test func testHitNamesAStalledAppsWindowFromTheList() {
    let pid: pid_t = 999_999
    let id = WindowID(UInt32.max - 1)
    let windows = Windows { [(id: id, pid: pid, frame: Frame(x: -90_000, y: -90_000, w: 100, h: 100))] }
    let p = Point(x: -89_950, y: -89_950)
    let now = ProcessInfo.processInfo.systemUptime
    // Test 0: Not stalled, so the system-wide ask runs and finds no such window.
    #expect(!windows.stalled(pid))
    #expect(windows.hit(p) != id)
    // Test 1: Stalled, so the listing names the window.
    windows.stall(pid, at: now)
    #expect(windows.stalled(pid))
    #expect(windows.stalledCount == 1)
    #expect(windows.hit(p) == id)
    #expect(windows.hit(CGPoint(x: p.x, y: p.y)) == nil)
    // Test 2: A stall older than stallSeconds has lapsed.
    windows.stall(pid, at: now - Windows.stallSeconds - 0.1)
    #expect(!windows.stalled(pid))
    #expect(windows.stalledCount == 0)
    // Test 3: A quit app's stall is forgotten.
    windows.stall(pid, at: now)
    windows.forget(pid)
    #expect(windows.stalls[pid] == nil)
}

// focused asks the window server for a window once, trusts that confirmation for PassPlan.fullSeconds
// and asks again after it, so a window its app floats is refused within the bound, while window always
// asks. It opens a real Probe window, so it runs only when MOORINGS_LIVE_CONTRACTS is 1, with
// Accessibility access.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MOORINGS_LIVE_CONTRACTS"] == "1",
        "MOORINGS_LIVE_CONTRACTS is not 1"),
    .enabled(if: AXIsProcessTrusted(), "this test host has no Accessibility access")
) @MainActor func testFocusedTrustsARecentConfirmation() {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: MacHost.probe) != nil else {
        Issue.record("the probe is not installed. Run make probe in mac/ first")
        return
    }
    _ = NSApplication.shared
    let host = MacHost(store: Windows())
    defer { host.finish() }
    guard let id = host.open() else {
        Issue.record("the probe opened no window")
        return
    }
    let screens = Screens.current()
    guard host.wait(until: host.now + 5, { host.store.focused(screens)?.id == id }) else {
        Issue.record("the probe window \(id) never had focus")
        return
    }
    var asked = 0
    let windows = Windows(lookup: { id in
        asked += 1
        return Windows.onScreen(id)
    })
    // Test 0: The first read asks, since nothing has confirmed the window yet.
    #expect(windows.focused(screens)?.id == id)
    #expect(asked == 1)
    // Test 1: The second read trusts the confirmation the first one made.
    #expect(windows.focused(screens)?.id == id)
    #expect(asked == 1)
    // Test 2: A confirmation older than fullSeconds is not trusted, so the read asks again.
    windows.backdate(id, by: PassPlan.fullSeconds + 1)
    #expect(windows.focused(screens)?.id == id)
    #expect(asked == 2)
    // Test 3: Reading the window by id always asks, however recent its confirmation.
    #expect(windows.window(id, screens: screens)?.id == id)
    #expect(asked == 3)
}

// testScanCountsRoundTrips scans with a Probe window open and counts the round trips of a scan of the
// desk and of a read of the probe alone, with its window ids cached and after they are forgotten. It
// runs only when MOORINGS_LIVE_CONTRACTS is 1, with Accessibility access.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MOORINGS_LIVE_CONTRACTS"] == "1",
        "MOORINGS_LIVE_CONTRACTS is not 1"),
    .enabled(if: AXIsProcessTrusted(), "this test host has no Accessibility access")
) @MainActor func testScanCountsRoundTrips() {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: MacHost.probe) != nil else {
        Issue.record("the probe is not installed. Run make probe in mac/ first")
        return
    }
    _ = NSApplication.shared
    let host = MacHost(store: Windows())
    defer { host.finish() }
    guard host.open() != nil else {
        Issue.record("the probe opened no window")
        return
    }
    let before = Windows.roundTrips
    _ = Windows().scan(Screens.current())
    // Test 0: A full scan of the desk costs at least one trip for the probe and two for its window.
    #expect(Windows.roundTrips - before >= 3)
    let store = Windows()
    let screens = Screens.current()
    let full = store.scan(screens)
    guard
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: MacHost.probe).first?.processIdentifier
    else {
        Issue.record("the probe is not running")
        return
    }
    let n = full.windows.filter { $0.bundle == MacHost.probe }.count
    let probeOnly:
        (_: [pid_t: [WindowID: Frame]], _: [pid_t: [WindowID: Frame]], _: Set<pid_t>, _: pid_t?) -> PassPlan = {
            _, _, _, _ in .apps([pid])
        }
    var at = Windows.roundTrips
    _ = store.scan(screens, decide: probeOnly)
    // Test 1: A second read of the probe costs one trip for the app and one per window for its traits,
    // since the ids are cached and the frames did not change.
    #expect(Windows.roundTrips - at == 1 + n, "probe windows \(n)")
    store.forget(pid)
    at = Windows.roundTrips
    _ = store.scan(screens, decide: probeOnly)
    // Test 2: After the probe is forgotten, its read asks each window's id again: one trip for the app
    // and two per window.
    #expect(Windows.roundTrips - at == 1 + 2 * n, "probe windows \(n)")
}

// testZoomRectMovesWithWindow moves a Probe window and reads the probe alone: the green button rect
// moves with the window at no cost, and a resize reads the button again. It runs only when
// MOORINGS_LIVE_CONTRACTS is 1, with Accessibility access.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MOORINGS_LIVE_CONTRACTS"] == "1",
        "MOORINGS_LIVE_CONTRACTS is not 1"),
    .enabled(if: AXIsProcessTrusted(), "this test host has no Accessibility access")
) @MainActor func testZoomRectMovesWithWindow() {
    _ = NSApplication.shared
    let host = MacHost(store: Windows())
    defer { host.finish() }
    guard let id = host.open(),
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: MacHost.probe).first?.processIdentifier
    else {
        Issue.record("the probe opened no window")
        return
    }
    let store = host.store
    let screens = Screens.current()
    let probeOnly:
        (_: [pid_t: [WindowID: Frame]], _: [pid_t: [WindowID: Frame]], _: Set<pid_t>, _: pid_t?) -> PassPlan = {
            _, _, _, _ in .apps([pid])
        }
    let read = { store.scan(screens, decide: probeOnly).windows.filter { $0.bundle == MacHost.probe } }
    let first = read()
    guard let was = first.first(where: { $0.id == id }), let rect = was.zoomRect else {
        Issue.record("the probe window has no green button rect")
        return
    }
    let n = first.count
    store.position(id, x: was.frame.x + 100, y: was.frame.y)
    _ = host.wait(until: host.now + 2) { store.frame(id).map { $0.x == was.frame.x + 100 } ?? false }
    var at = Windows.roundTrips
    let moved = read().first { $0.id == id }
    // Test 0: A pure move costs one trip for the app and one per window for its traits, and the rect
    // moves with the window.
    #expect(Windows.roundTrips - at == 1 + n, "probe windows \(n)")
    #expect(moved?.zoomRect == Frame(x: rect.x + 100, y: rect.y, w: rect.w, h: rect.h))
    store.resize(id, w: was.frame.w + 40, h: was.frame.h)
    _ = host.wait(until: host.now + 2) { store.frame(id).map { $0.w == was.frame.w + 40 } ?? false }
    at = Windows.roundTrips
    _ = read()
    // Test 1: A resize reads the green button again, its position and its size.
    #expect(Windows.roundTrips - at == 1 + n + 2, "probe windows \(n)")
}
