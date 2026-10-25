import Foundation
import Testing

@testable import MooringsCore

// Flag bits as CGEventFlags reports them.
let flagShift: UInt64 = 0x20000
let flagControl: UInt64 = 0x40000
let flagOption: UInt64 = 0x80000
let flagCommand: UInt64 = 0x100000
let flagLeftOption: UInt64 = 0x20
let flagRightOption: UInt64 = 0x40
let flagRightCommand: UInt64 = 0x10
let flagRightControl: UInt64 = 0x2000
let flagFn: UInt64 = 0x800000

// Swift only: each trigger is held only on its own key, with shift allowed and no other modifier.
@Test func testOverlayTriggerHeld() {
    let tests: [(trigger: OverlayTrigger, flags: UInt64, want: Bool)] = [
        // Test 0: Right Option alone.
        (.rightOption, flagOption | flagRightOption, true),
        // Test 1: Left Option alone is not the trigger.
        (.rightOption, flagOption | flagLeftOption, false),
        // Test 2: Right Option with Shift still holds.
        (.rightOption, flagOption | flagRightOption | flagShift, true),
        // Test 3: Right Option with Command is a different chord.
        (.rightOption, flagOption | flagRightOption | flagCommand, false),
        // Test 4: Right Option with Control is a different chord.
        (.rightOption, flagOption | flagRightOption | flagControl, false),
        // Test 5: Right Command alone.
        (.rightCommand, flagCommand | flagRightCommand, true),
        // Test 6: Right Command with Option is a different chord.
        (.rightCommand, flagCommand | flagRightCommand | flagOption, false),
        // Test 7: Right Control alone.
        (.rightControl, flagControl | flagRightControl, true),
        // Test 8: Fn alone.
        (.fn, flagFn, true),
        // Test 9: Fn with Shift.
        (.fn, flagFn | flagShift, true),
        // Test 10: Fn with Option is a different chord.
        (.fn, flagFn | flagOption, false),
        // Test 11: None reacts to nothing.
        (.none, flagOption | flagRightOption, false),
        // Test 12: None reacts to no flags.
        (.none, 0, false),
        // Test 13: Nothing down.
        (.rightOption, 0, false),
    ]
    for (i, test) in tests.enumerated() {
        #expect(test.trigger.held(test.flags) == test.want, "test \(i)")
    }
}

// Swift only: the cursor picker reads 16 targets in two rings and nothing inside the dead zone.
@Test func testOverlayPick() {
    let tests: [(dx: Double, dy: Double, want: String?)] = [
        // Test 0: Still.
        (0, 0, nil),
        // Test 1: Just inside the dead zone.
        (23.9, 0, nil),
        // Test 2: On the dead zone edge picks.
        (24, 0, "right-half"),
        // Test 3: Up is a negative dy.
        (0, -50, "top-half"),
        // Test 4: Down.
        (0, 50, "bottom-half"),
        // Test 5: Left.
        (-50, 0, "left-half"),
        // Test 6: Up and right.
        (50, -50, "top-right"),
        // Test 7: Up and left.
        (-50, -50, "top-left"),
        // Test 8: Down and left.
        (-50, 50, "bottom-left"),
        // Test 9: Down and right.
        (50, 50, "bottom-right"),
        // Test 10: Just inside the ring.
        (159.9, 0, "right-half"),
        // Test 11: On the ring picks the outer target.
        (160, 0, "last-third"),
        // Test 12: Outer up.
        (0, -200, "maximize"),
        // Test 13: Outer down.
        (0, 200, "center"),
        // Test 14: Outer left.
        (-200, 0, "first-third"),
        // Test 15: Outer up and right.
        (150, -150, "top-right-sixth"),
        // Test 16: Outer up and left.
        (-150, -150, "top-left-sixth"),
        // Test 17: Outer down and left.
        (-150, 150, "bottom-left-sixth"),
        // Test 18: Outer down and right.
        (150, 150, "bottom-right-sixth"),
        // Test 19: Just below 22.5 degrees stays right.
        (100, -41, "right-half"),
        // Test 20: Just above 22.5 degrees turns to top right.
        (100, -42, "top-right"),
        // Test 21: Just below the axis on the right stays right.
        (100, 1, "right-half"),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Overlay.pick(dx: test.dx, dy: test.dy) == test.want, "test \(i)")
    }
}

// Swift only: every overlay target is a known action that places a frame.
@Test func testOverlayTargetsKnown() {
    #expect(Set(Overlay.inner + Overlay.outer).count == 16)
    for name in Overlay.inner + Overlay.outer {
        #expect(Keymaps.known(name), "\(name)")
        #expect(Geometry.position(name, F(0, 0, 1200, 600)) != nil || name == "center", "\(name)")
    }
}

// span returns the grid's span as c0, c1, r0, r1.
func span(_ g: OverlayGrid) -> [Int] {
    [g.c0, g.c1, g.r0, g.r1]
}

// Swift only: the keyboard grid starts on the cell under the pointer, moves and grows inside the grid,
// and gives the span's frame.
@Test func testOverlayGrid() {
    let area = F(0, 0, 1200, 800)
    let g = OverlayGrid(cols: 6, rows: 4, at: Point(x: 650, y: 410), in: area)
    #expect(span(g) == [3, 4, 2, 3])
    #expect(g.frame(area) == F(600, 400, 200, 200))
    let corner = OverlayGrid(cols: 6, rows: 4, at: Point(x: -50, y: 5000), in: area)
    #expect(corner.c0 == 0 && corner.r0 == 3)
    #expect(corner.moved(.left) == corner)
    #expect(corner.moved(.down) == corner)
    let up = corner.moved(.up).moved(.right)
    #expect(span(up) == [1, 2, 2, 3])
    var big = up
    for _ in 0..<10 {
        big = big.grown(.right).grown(.up)
    }
    #expect(span(big) == [1, 6, 0, 3])
    #expect(big.moved(.right) == big)
    #expect(big.moved(.up) == big)
    #expect(big.grown(.left).frame(area) == F(0, 0, 1200, 600))
    #expect(big.frame(area, gap: 10) == Geometry.part(area, 1, 6, 6, 0, 3, 4, gap: 10))
    let one = OverlayGrid(cols: 0, rows: 0, at: Point(x: 0, y: 0), in: F(0, 0, 0, 0))
    #expect(one.frame(area) == area)
}

// Swift only: overlay choices default to no trigger, load missing or bad fields as defaults, clamp the
// grid and round trip.
@Test func testOverlayChoicesDecode() throws {
    #expect(Choices.decode(Data(#"{"snap":true}"#.utf8)).overlay == OverlayChoices())
    #expect(OverlayChoices().trigger == .none)
    #expect(try JSONDecoder().decode(OverlayChoices.self, from: Data("{}".utf8)) == OverlayChoices())
    let bad = Data(#"{"trigger":"capsLock","gridColumns":99,"gridRows":0}"#.utf8)
    let o = try JSONDecoder().decode(OverlayChoices.self, from: bad)
    #expect(o.trigger == .none && o.gridColumns == 12 && o.gridRows == 1)
    var c = Choices()
    c.overlay.trigger = .fn
    c.overlay.gridColumns = 8
    #expect(Choices.decode(try Choices.encode(c)) == c)
}
