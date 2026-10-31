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
