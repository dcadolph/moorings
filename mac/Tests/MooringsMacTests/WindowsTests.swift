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
