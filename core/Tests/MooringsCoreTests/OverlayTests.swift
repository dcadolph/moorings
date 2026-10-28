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

// Swift only: a drag across the grid picks every cell between the two points, either way round, and
// a point off the area takes the nearest cell.
@Test func testOverlayGridSpan() {
    let area = F(100, 50, 1200, 800)
    let tests: [(a: Point, b: Point, want: [Int])] = [
        // Test 0: One cell, press and release in place.
        (Point(x: 150, y: 60), Point(x: 160, y: 70), [0, 1, 0, 1]),
        // Test 1: Top left to bottom right.
        (Point(x: 150, y: 60), Point(x: 750, y: 500), [0, 4, 0, 3]),
        // Test 2: Bottom right to top left gives the same span.
        (Point(x: 750, y: 500), Point(x: 150, y: 60), [0, 4, 0, 3]),
        // Test 3: Up and to the right.
        (Point(x: 350, y: 800), Point(x: 1250, y: 300), [1, 6, 1, 4]),
        // Test 4: Off the area clamps to the edge cells.
        (Point(x: -500, y: -500), Point(x: 9000, y: 9000), [0, 6, 0, 4]),
    ]
    for (i, test) in tests.enumerated() {
        #expect(span(OverlayGrid(cols: 6, rows: 4, from: test.a, to: test.b, in: area)) == test.want, "test \(i)")
    }
    let g = OverlayGrid(cols: 6, rows: 4, from: Point(x: 150, y: 60), to: Point(x: 750, y: 500), in: area)
    #expect(g.frame(area) == F(100, 50, 800, 600))
}

// Swift only: grid takes the overlay's size, grid:CxR its own inside gridRange, and anything else is
// no grid action.
@Test func testOverlayGridSize() {
    var o = OverlayChoices()
    o.gridColumns = 5
    o.gridRows = 3
    let tests: [(name: String, want: [Int]?)] = [
        // Test 0: Plain grid takes the choices.
        ("grid", [5, 3]),
        // Test 1: Own size.
        ("grid:8x6", [8, 6]),
        // Test 2: Bounds of the range.
        ("grid:1x12", [1, 12]),
        // Test 3: Past the range.
        ("grid:13x2", nil),
        // Test 4: Zero.
        ("grid:0x4", nil),
        // Test 5: Missing rows.
        ("grid:8", nil),
        // Test 6: Missing rows after the x.
        ("grid:8x", nil),
        // Test 7: Not a number.
        ("grid:axb", nil),
        // Test 8: Not a grid action.
        ("grids", nil),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Overlay.gridSize(test.name, o).map { [$0.cols, $0.rows] } == test.want, "test \(i)")
    }
    #expect(Keymaps.known("grid") && Keymaps.known("grid:8x6"))
    #expect(!Keymaps.known("grid:99x6"))
    #expect(Keymaps.label("grid:8x6") == "Grid 8 by 6")
    #expect(Keymaps.label("grid") == "Grid")
}

// Swift only: hover moves on exactly the move set and resizes on exactly the resize set; Shift alone,
// an empty set and a resize set equal to the move set do nothing.
@Test func testHoverMode() {
    var o = OverlayChoices()
    o.hoverMove = [.ctrl, .alt]
    o.hoverResize = [.ctrl, .alt, .shift]
    let tests: [(choices: OverlayChoices, flags: UInt64, want: HoverMode?)] = [
        // Test 0: Exactly the move set.
        (o, flagControl | flagOption, .move),
        // Test 1: Device bits ride along.
        (o, flagControl | flagOption | flagRightOption, .move),
        // Test 2: Exactly the resize set.
        (o, flagControl | flagOption | flagShift, .resize),
        // Test 3: One more modifier than either set.
        (o, flagControl | flagOption | flagCommand, nil),
        // Test 4: Part of the move set.
        (o, flagControl, nil),
        // Test 5: Nothing held.
        (o, 0, nil),
        // Test 6: Off by default.
        (OverlayChoices(), flagControl | flagOption, nil),
        // Test 7: Shift alone never drives a hover.
        (
            {
                var c = OverlayChoices(); c.hoverMove = [.shift]; return c
            }(), flagShift, nil
        ),
        // Test 8: A resize set equal to the move set moves.
        (
            {
                var c = o; c.hoverResize = [.alt, .ctrl]; return c
            }(), flagControl | flagOption, .move
        ),
        // Test 9: Resize alone.
        (
            {
                var c = OverlayChoices(); c.hoverResize = [.cmd]; return c
            }(), flagCommand, .resize
        ),
    ]
    for (i, test) in tests.enumerated() {
        #expect(Hover.mode(test.flags, test.choices) == test.want, "test \(i)")
    }
}

// Swift only: a hover move follows the pointer; a resize moves the nearest corner, keeps the opposite
// one fixed and stops at the minimum.
@Test func testHoverFrame() {
    let start = F(100, 100, 400, 300)
    #expect(Hover.corner(start, nearest: Point(x: 120, y: 110)) == .topLeft)
    #expect(Hover.corner(start, nearest: Point(x: 480, y: 110)) == .topRight)
    #expect(Hover.corner(start, nearest: Point(x: 120, y: 390)) == .bottomLeft)
    #expect(Hover.corner(start, nearest: Point(x: 480, y: 390)) == .bottomRight)
    let tests: [(mode: HoverMode, corner: HoverCorner, dx: Double, dy: Double, want: Frame)] = [
        // Test 0: Move.
        (.move, .topLeft, 30, -20, F(130, 80, 400, 300)),
        // Test 1: Bottom right grows.
        (.resize, .bottomRight, 50, 40, F(100, 100, 450, 340)),
        // Test 2: Top left grows up and left, bottom right corner fixed.
        (.resize, .topLeft, -50, -40, F(50, 60, 450, 340)),
        // Test 3: Top right shrinks, bottom left corner fixed.
        (.resize, .topRight, -100, 100, F(100, 200, 300, 200)),
        // Test 4: Bottom left past the minimum stops there, right edge fixed.
        (.resize, .bottomLeft, 1000, -1000, F(340, 100, 160, 100)),
    ]
    for (i, test) in tests.enumerated() {
        #expect(
            Hover.frame(test.mode, start: start, corner: test.corner, dx: test.dx, dy: test.dy) == test.want,
            "test \(i)")
    }
    // An app that keeps a larger size than asked moves only the corner that follows the pointer.
    #expect(Hover.keep(start, corner: .topLeft, w: 380, h: 300) == F(120, 100, 380, 300))
    #expect(Hover.keep(start, corner: .bottomRight, w: 380, h: 290) == F(100, 100, 380, 290))
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
    c.overlay.hoverMove = [.ctrl, .alt]
    c.overlay.hoverResize = [.cmd]
    #expect(Choices.decode(try Choices.encode(c)) == c)
    let mods = Data(#"{"hoverMove":["option","Control","option","hyper"],"hoverResize":7}"#.utf8)
    let h = try JSONDecoder().decode(OverlayChoices.self, from: mods)
    #expect(h.hoverMove == [.ctrl, .alt] && h.hoverResize.isEmpty)
}

// Swift only: the macOS Option tiling note shows for a Right Option trigger and for hover keys that
// are Option alone, and the Spaces note only for a Right Control trigger.
@Test func testOverlayMeetsTiling() {
    let tests: [(trigger: OverlayTrigger, move: [Modifier], resize: [Modifier], wantTrigger: Bool, wantHover: Bool)] = [
        // Test 0: Defaults show neither note.
        (.none, [], [], false, false),
        // Test 1: Right Option trigger.
        (.rightOption, [], [], true, false),
        // Test 2: Right Command trigger.
        (.rightCommand, [], [], false, false),
        // Test 3: Fn trigger.
        (.fn, [], [], false, false),
        // Test 4: Hover move is Option alone.
        (.none, [.alt], [], false, true),
        // Test 5: Hover resize is Option alone.
        (.none, [.ctrl], [.alt], false, true),
        // Test 6: Option with Control is a different chord.
        (.none, [.ctrl, .alt], [.ctrl, .alt, .shift], false, false),
        // Test 7: Both at once.
        (.rightOption, [.alt], [], true, true),
        // Test 8: Right Control trigger shows only the Spaces note.
        (.rightControl, [], [], false, false),
    ]
    for (i, test) in tests.enumerated() {
        var o = OverlayChoices()
        o.trigger = test.trigger
        o.hoverMove = test.move
        o.hoverResize = test.resize
        #expect(o.triggerMeetsTiling == test.wantTrigger, "test \(i)")
        #expect(o.hoverMeetsTiling == test.wantHover, "test \(i)")
        #expect(o.gridMeetsSpaces == (test.trigger == .rightControl), "test \(i)")
    }
}
