import CoreGraphics
import Testing

import MooringsCore

@testable import Moorings

// The key tap delivers a claimed key only with exactly its modifiers, ignores the Fn and keypad bits
// arrow keys carry, swallows a claimed key's repeats without delivering them, and passes the rest.
@Test func testKeyTapMatch() {
    let claims = [
        KeyClaim(code: 123, modifiers: .control, tag: "back"),
        KeyClaim(code: 124, modifiers: .control, tag: "on"),
    ]
    let arrow = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskNumericPad.rawValue
    let ctrl = CGEventFlags.maskControl.rawValue
    let tests: [(code: Int, flags: UInt64, repeating: Bool, want: KeyMatch)] = [
        // Test 0: Control-Right as the keyboard sends it.
        (124, ctrl | arrow, false, .deliver("on")),
        // Test 1: Control-Left with no Fn or keypad bits.
        (123, ctrl, false, .deliver("back")),
        // Test 2: A held Control-Right repeats and is swallowed without delivering.
        (124, ctrl | arrow, true, .swallow),
        // Test 3: Right Control alone counts as Control.
        (124, ctrl | 0x2000 | arrow, false, .deliver("on")),
        // Test 4: Control-Option-Right is another shortcut and passes.
        (124, ctrl | CGEventFlags.maskAlternate.rawValue | arrow, false, .pass),
        // Test 5: Control-Shift-Right passes.
        (124, ctrl | CGEventFlags.maskShift.rawValue | arrow, false, .pass),
        // Test 6: Control-Command-Right passes.
        (124, ctrl | CGEventFlags.maskCommand.rawValue | arrow, false, .pass),
        // Test 7: Right arrow alone passes.
        (124, arrow, false, .pass),
        // Test 8: Control-Up is not claimed and passes.
        (126, ctrl | arrow, false, .pass),
        // Test 9: A letter passes.
        (7, 0, false, .pass),
    ]
    for (testNum, test) in tests.enumerated() {
        let got = KeyTap.match(
            claims, code: test.code, flags: CGEventFlags(rawValue: test.flags), repeating: test.repeating)
        #expect(got == test.want, "test \(testNum)")
    }
    #expect(KeyTap.match([], code: 124, flags: CGEventFlags(rawValue: ctrl), repeating: false) == .pass)
}
