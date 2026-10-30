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
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime)
    _ = windows.scan(screens, full: false)
    #expect(asked == 1)
    // Test 1: Nothing placed since the last scan, so the scan asks.
    _ = windows.scan(screens, full: false)
    #expect(asked == 2)
    // Test 2: A placement and an app's event since the last scan, so the scan asks.
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime)
    windows.appWoke[999_999] = ProcessInfo.processInfo.systemUptime
    _ = windows.scan(screens, full: false)
    #expect(asked == 3)
    // Test 3: A forced scan asks even right after a placement.
    windows.echoes[1] = (moved, ProcessInfo.processInfo.systemUptime)
    _ = windows.scan(screens, full: true)
    #expect(asked == 4)
}
