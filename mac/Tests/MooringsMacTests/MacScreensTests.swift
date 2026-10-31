import Foundation
import Testing

import MooringsCore
import MooringsEngine

@testable import Moorings

// MacScreens reuses a quirks read for the same screens inside ttl and reads again past it or when
// the screens change.
@MainActor
@Test func testMacScreensQuirksCache() {
    let wide = Screens(
        full: [Frame(x: 0, y: 0, w: 5120, h: 1440)], usable: [Frame(x: 0, y: 25, w: 5120, h: 1415)], ultrawide: 0)
    let laptop = Screens(
        full: [Frame(x: 0, y: 0, w: 1728, h: 1117)], usable: [Frame(x: 0, y: 38, w: 1728, h: 1079)], ultrawide: nil)
    let tests: [(calls: [(at: Double, screens: Screens)], wantReads: Int)] = [
        // Test 0: Two calls 1 s apart on the same screens read once.
        ([(0, wide), (1, wide)], 1),
        // Test 1: A call past ttl reads again.
        ([(0, wide), (1, wide), (2.5, wide)], 2),
        // Test 2: Other screens inside ttl read again.
        ([(0, wide), (0.5, laptop)], 2),
        // Test 3: Back to the first screens reads again, since only the last read is kept.
        ([(0, wide), (0.5, laptop), (1, wide)], 3),
    ]
    for (i, test) in tests.enumerated() {
        let start = ContinuousClock.now
        var t = 0.0
        var reads = 0
        let subject = MacScreens(
            read: { _ in
                reads += 1
                return ScreenQuirks(notched: [reads])
            },
            now: { start.advanced(by: .milliseconds(Int(t * 1000))) })
        var last = ScreenQuirks()
        for call in test.calls {
            t = call.at
            last = subject.quirks(call.screens)
        }
        #expect(reads == test.wantReads, "test \(i)")
        #expect(last == ScreenQuirks(notched: [reads]), "test \(i)")
    }
}
