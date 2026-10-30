import CoreGraphics
import Testing

@testable import Moorings

// Selftest refuses to start while the system reads a modifier as held, and names each one.
@Test func testSelftestHeld() {
    let tests: [(flags: UInt64, want: String?)] = [
        // Test 0: Nothing down.
        (0, nil),
        // Test 1: The non-coalesced bit and a device bit alone hold no key.
        (0x2000_0000 | 0x100, nil),
        // Test 2: Option, as read on the owner's desk on 10-30.
        (0x2008_0000, "The system reads Option as held. Press and release it, then run again"),
        // Test 3: Control and Command.
        (0x40000 | 0x100000, "The system reads Control and Command as held. Press and release them, then run again"),
        // Test 4: Fn alone does not change a drag.
        (0x800000, nil),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Selftest.held(CGEventFlags(rawValue: test.flags)) == test.want, "test \(i)")
    }
}
