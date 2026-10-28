import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// Holding the move modifiers moves the window under the pointer by the pointer's travel, through
// position alone, and letting go wakes the passes.
@Test func testHoverMove() {
    let rig = HoldRig()
    rig.at = Point(x: 1500, y: 400)
    rig.hover.flagsChanged(HoldRig.ctrlAlt, at: rig.at)
    rig.clock.advance(by: 0)
    #expect(rig.hover.active)
    rig.at = Point(x: 1550.4, y: 430)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.frame == Frame(x: 1450, y: 330, w: 900, h: 700))
    #expect(rig.windows.calls.contains(.position(rig.pad, x: 1450, y: 330)))
    #expect(!rig.windows.calls.contains { if case .move = $0 { true } else { false } })
    rig.engine.passes.stop()
    rig.release()
    #expect(!rig.hover.active)
    #expect(rig.engine.passes.due != nil)
    #expect(rig.hoverTicks.pendingAt == nil)
}

// A still pointer writes nothing on later ticks.
@Test func testHoverStill() {
    let rig = HoldRig()
    rig.at = Point(x: 1500, y: 400)
    rig.hover.flagsChanged(HoldRig.ctrlAlt, at: rig.at)
    rig.clock.advance(by: 0)
    rig.at = Point(x: 1510, y: 400)
    rig.clock.advance(by: HoverMover.tickSeconds)
    let moves = rig.moves
    rig.clock.advance(by: HoverMover.tickSeconds * 5)
    #expect(rig.moves == moves)
}

// Holding the resize modifiers near the bottom-right corner grows the window with its top-left fixed.
@Test func testHoverResize() {
    let rig = HoldRig()
    rig.at = Point(x: 2200, y: 900)
    rig.hover.flagsChanged(HoldRig.ctrlCmd, at: rig.at)
    rig.clock.advance(by: 0)
    rig.at = Point(x: 2250, y: 940)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.frame == Frame(x: 1400, y: 300, w: 950, h: 740))
}

// A resize from the top-left corner that the window refuses below its minimum keeps the right and
// bottom edges where they were.
@Test func testHoverResizeMinimum() {
    let rig = HoldRig()
    let small = rig.windows.add(bundle: "com.example.small", frame: Frame(x: 500, y: 300, w: 600, h: 500), minW: 550)
    rig.at = Point(x: 510, y: 310)
    rig.hover.flagsChanged(HoldRig.ctrlCmd, at: rig.at)
    rig.clock.advance(by: 0)
    rig.at = Point(x: 610, y: 310)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.windows.frame(small) == Frame(x: 550, y: 300, w: 550, h: 500))
}

// Nothing moves while a mouse button is down.
@Test func testHoverButtonDown() {
    let rig = HoldRig()
    rig.at = Point(x: 1500, y: 400)
    rig.hover.flagsChanged(HoldRig.ctrlAlt, at: rig.at)
    rig.clock.advance(by: 0)
    rig.down = true
    rig.at = Point(x: 1600, y: 400)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.frame == Frame(x: 1400, y: 300, w: 900, h: 700))
}

// Stashed and pinned windows, a held trigger, and no window under the pointer start no hover.
@Test func testHoverLeftAlone() {
    let stashed = HoldRig()
    stashed.anchors.stashed.insert(stashed.pad)
    let pinned = HoldRig { $0.slots = [.leftTop: "com.example.pad"] }
    pinned.moor()
    #expect(pinned.anchors.pinned(pinned.windows.scan(pinned.screens.current(), full: true).windows[0]))
    let empty = HoldRig()
    let off = Point(x: 500, y: 1200)
    for (rig, start) in [(stashed, center(stashed.frame)), (pinned, center(pinned.frame)), (empty, off)] {
        let before = rig.frame
        let moves = rig.moves
        rig.at = start
        rig.hover.flagsChanged(HoldRig.ctrlAlt, at: rig.at)
        rig.clock.advance(by: 0)
        rig.at = Point(x: start.x + 100, y: start.y)
        rig.clock.advance(by: HoverMover.tickSeconds)
        #expect(!rig.hover.active)
        #expect(rig.frame == before)
        #expect(rig.moves == moves)
        #expect(rig.logs == ["hover: no free window under the pointer"])
    }
    let trigger = HoldRig { $0.overlay.hoverMove = [.alt] }
    trigger.hover.flagsChanged(HoldRig.rightOption, at: Point(x: 1500, y: 400))
    trigger.clock.advance(by: 0)
    #expect(!trigger.hover.active)
}

// A paused Moorings starts no hover and says why.
@Test func testHoverPaused() {
    let rig = HoldRig { $0.paused = true }
    rig.hover.flagsChanged(HoldRig.ctrlAlt, at: Point(x: 1500, y: 400))
    rig.clock.advance(by: 0)
    #expect(!rig.hover.active)
    #expect(rig.logs == ["hover: keys held but moorings is paused: nothing moves"])
    #expect(rig.hoverTicks.pendingAt == nil)
}

// Switching from the move set to the resize set restarts the hover from where the pointer is.
@Test func testHoverSwitch() {
    let rig = HoldRig()
    rig.at = Point(x: 2200, y: 900)
    rig.hover.flagsChanged(HoldRig.ctrlAlt, at: rig.at)
    rig.clock.advance(by: 0)
    rig.at = Point(x: 2210, y: 900)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.frame == Frame(x: 1410, y: 300, w: 900, h: 700))
    rig.engine.passes.stop()
    rig.hover.flagsChanged(HoldRig.ctrlCmd, at: rig.at)
    #expect(rig.engine.passes.due != nil)
    rig.clock.advance(by: 0)
    rig.at = Point(x: 2240, y: 900)
    rig.clock.advance(by: HoverMover.tickSeconds)
    #expect(rig.frame == Frame(x: 1410, y: 300, w: 930, h: 700))
}
