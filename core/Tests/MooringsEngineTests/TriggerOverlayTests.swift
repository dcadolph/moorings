import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// rightHalf is the right half of the fake ultrawide's usable area.
let rightHalf = Frame(x: 1720, y: 25, w: 1720, h: 1415)

// Holding the trigger and moving right previews the right half, and letting go throws the window there.
@Test func testThrowRight() {
    let rig = HoldRig()
    rig.press(at: Point(x: 2000, y: 700))
    #expect(rig.grabs == [.rightOption])
    rig.point(Point(x: 2100, y: 700))
    #expect(rig.footprint.shown == rightHalf)
    rig.release()
    #expect(rig.frame == rightHalf)
    #expect(rig.footprint.shown == nil)
    #expect(rig.ungrabs == 1)
}

// Letting go inside the dead zone moves nothing.
@Test func testThrowDeadZone() {
    let rig = HoldRig()
    rig.press(at: Point(x: 2000, y: 700))
    rig.point(Point(x: 2010, y: 700))
    rig.release()
    #expect(rig.moves == 0)
    #expect(rig.footprint.shown == nil)
}

// Escape ends the hold, and letting go after it moves nothing.
@Test func testThrowEscape() {
    let rig = HoldRig()
    rig.press(at: Point(x: 2000, y: 700))
    rig.point(Point(x: 2100, y: 700))
    rig.overlay.key("escape")
    #expect(rig.footprint.shown == nil)
    rig.release()
    #expect(rig.moves == 0)
}

// A grid key shows the grid at the pointer, a move key shifts the span, and Return applies it.
@Test func testThrowGridKeys() {
    let rig = HoldRig()
    rig.press(at: Point(x: 100, y: 100))
    rig.overlay.key("move-right")
    let area = Frame(x: 0, y: 25, w: 3440, h: 1415)
    let first = OverlayGrid(cols: 6, rows: 4, at: Point(x: 100, y: 100), in: area)
    #expect(rig.throwGrid.shown == GridMark(grid: first, area: area))
    rig.overlay.key("move-right")
    let second = first.moved(.right)
    #expect(rig.throwGrid.shown == GridMark(grid: second, area: area))
    rig.overlay.key("return")
    #expect(rig.frame == second.frame(area))
    #expect(rig.throwGrid.shown == nil)
    rig.release()
    #expect(rig.frame == second.frame(area))
}

// A grid span used and then the trigger let go applies the span, not the cursor pick.
@Test func testThrowGridOnRelease() {
    let rig = HoldRig()
    rig.press(at: Point(x: 100, y: 100))
    rig.overlay.key("move-down")
    rig.point(Point(x: 3000, y: 100))
    #expect(rig.footprint.shown == nil)
    rig.release()
    let area = Frame(x: 0, y: 25, w: 3440, h: 1415)
    #expect(rig.frame == OverlayGrid(cols: 6, rows: 4, at: Point(x: 100, y: 100), in: area).frame(area))
}

// A paused Moorings, shortcuts off, or a button down stops a hold before it grabs a key.
@Test func testThrowBlocked() {
    let paused = HoldRig { $0.paused = true }
    paused.press(at: Point(x: 2000, y: 700))
    #expect(paused.grabs.isEmpty)
    #expect(paused.logs == ["overlay: trigger held but moorings is paused: nothing to throw"])
    let off = HoldRig()
    off.shortcuts = false
    off.press(at: Point(x: 2000, y: 700))
    #expect(off.logs == ["overlay: trigger held but shortcuts are off: nothing to throw"])
    let button = HoldRig()
    button.down = true
    button.press(at: Point(x: 2000, y: 700))
    #expect(button.logs == ["overlay: trigger held but a mouse button is down: nothing to throw"])
    for rig in [paused, off, button] {
        rig.point(Point(x: 2100, y: 700))
        rig.release()
        #expect(rig.moves == 0)
    }
}

// With no window under the pointer the focused one is thrown, and with neither nothing is.
@Test func testThrowTarget() {
    let focused = HoldRig()
    focused.under = nil
    focused.press(at: Point(x: 2000, y: 700))
    focused.point(Point(x: 2100, y: 700))
    focused.release()
    #expect(focused.frame == rightHalf)
    let none = HoldRig()
    none.under = nil
    none.windows.focusedID = nil
    none.press(at: Point(x: 2000, y: 700))
    none.point(Point(x: 2100, y: 700))
    none.release()
    #expect(none.moves == 0)
    #expect(none.logs == ["overlay: no window to throw under the pointer or in front"])
}

// Letting go with a mouse button down throws nothing.
@Test func testThrowButtonAtRelease() {
    let rig = HoldRig()
    rig.press(at: Point(x: 2000, y: 700))
    rig.point(Point(x: 2100, y: 700))
    rig.down = true
    rig.release()
    #expect(rig.moves == 0)
    #expect(rig.logs == ["overlay: trigger let go while a mouse button is down: nothing thrown"])
}

// Letting go before the first tick read a window throws nothing.
@Test func testThrowReleaseBeforeRead() {
    let rig = HoldRig()
    rig.overlay.flagsChanged(HoldRig.rightOption, at: Point(x: 2000, y: 700))
    rig.at = Point(x: 2100, y: 700)
    rig.release()
    #expect(rig.moves == 0)
}

// Nothing is scheduled once the hold is over, so a resting trigger costs nothing.
@Test func testThrowIdleAfterRelease() {
    let rig = HoldRig()
    rig.press(at: Point(x: 2000, y: 700))
    #expect(rig.throwTicks.pendingAt != nil)
    rig.point(Point(x: 2100, y: 700))
    rig.release()
    #expect(rig.throwTicks.pendingAt == nil)
    let runs = rig.throwTicks.runs
    rig.clock.advance(by: 1)
    #expect(rig.throwTicks.runs == runs)
}

// Another modifier with the trigger does not count as the trigger held.
@Test func testThrowOtherModifier() {
    let rig = HoldRig()
    rig.at = Point(x: 2000, y: 700)
    rig.overlay.flagsChanged(HoldRig.rightOption | 0x100000, at: rig.at)
    rig.clock.advance(by: 0)
    #expect(rig.grabs.isEmpty)
}

// A hold puts an open grid picker away.
@Test func testThrowCancelsPicker() {
    let rig = HoldRig()
    #expect(rig.picker.show(cols: 2, rows: 2, window: nil))
    rig.press(at: Point(x: 2000, y: 700))
    #expect(!rig.picker.showing)
    #expect(rig.pickerGrid.shown == nil)
}

// The grid key tags name their directions, and other tags name none.
@Test func testThrowStep() {
    #expect(TriggerOverlay.step("move-left") == .left)
    #expect(TriggerOverlay.step("grow-down") == .down)
    #expect(TriggerOverlay.step("move-up") == .up)
    #expect(TriggerOverlay.step("grow-right") == .right)
    #expect(TriggerOverlay.step("return") == nil)
}
