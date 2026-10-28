import CoreGraphics
import Testing

import MooringsCore

@testable import Moorings

// The Mac reads each CGEventFlags bit as one key, the right-hand device bits and Fn included, without
// Accessibility.
@Test func testModifiersFromFlags() {
    let tests: [(flags: UInt64, want: Modifiers)] = [
        // Test 0: Nothing down.
        (0, []),
        // Test 1: Left Option sets Option and its own left device bit, which has no key.
        (0x80000 | 0x20, .option),
        // Test 2: Right Option.
        (0x80000 | 0x40, [.option, .rightOption]),
        // Test 3: Right Command.
        (0x100000 | 0x10, [.command, .rightCommand]),
        // Test 4: Right Control.
        (0x40000 | 0x2000, [.control, .rightControl]),
        // Test 5: Right Shift.
        (0x20000 | 0x04, [.shift, .rightShift]),
        // Test 6: Fn.
        (0x800000, .function),
        // Test 7: Control and Option from the left.
        (0x40000 | 0x80000 | 0x01 | 0x20, [.control, .option]),
        // Test 8: Every side-free key.
        (0x20000 | 0x40000 | 0x80000 | 0x100000, [.shift, .control, .option, .command]),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Modifiers(flags: CGEventFlags(rawValue: test.flags)) == test.want, "test \(i)")
    }
}
