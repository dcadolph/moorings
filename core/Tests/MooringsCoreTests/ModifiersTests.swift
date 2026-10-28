import Foundation
import Testing

@testable import MooringsCore

// Swift only: saved modifier names read as keys, and a name no key holds reads as nil.
@Test func testModifiersNames() {
    let tests: [(names: [String], want: Modifiers?)] = [
        // Test 0: No names hold nothing.
        ([], []),
        // Test 1: Every name.
        (["shift", "control", "option", "command"], [.shift, .control, .option, .command]),
        // Test 2: A repeat counts once.
        (["command", "command"], .command),
        // Test 3: An unknown name.
        (["command", "hyper"], nil),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Modifiers(names: test.names) == test.want, "test \(i)")
    }
}

// Swift only: shortcut modifiers convert both ways, in menu order, and right-hand bits and Fn add no
// shortcut modifier.
@Test func testModifiersShortcut() {
    #expect(Modifiers([.cmd, .ctrl]) == [.control, .command])
    #expect(Modifiers([.shift, .ctrl, .alt, .cmd]).shortcut == [.ctrl, .alt, .shift, .cmd])
    #expect(Modifiers([.option, .rightOption, .function]).shortcut == [.alt])
    #expect(Modifiers().shortcut.isEmpty)
}

// Swift only: snapping that names a key no one can hold never snaps, and the named keys must be held.
@Test func testSnapZoneNeedsNamedKeys() {
    var m = SnapChoices()
    m.snapModifiers = ["hyper"]
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m, held: .shift) == nil)
    m.snapModifiers = ["shift", "command"]
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m, held: .shift) == nil)
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m, held: [.shift, .command]) == "left-half")
}
