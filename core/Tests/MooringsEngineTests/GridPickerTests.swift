import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// usableArea is the fake ultrawide's usable area, which a window with no slots divides.
let usableArea = Frame(x: 0, y: 25, w: 3440, h: 1415)

// The grid opens over the focused window's area at the pointer, keys move and grow the span, and
// Return fills it and puts the grid away.
@Test func testGridKeys() {
    let rig = HoldRig()
    rig.at = Point(x: 100, y: 100)
    #expect(rig.picker.show(cols: 4, rows: 2, window: nil))
    #expect(rig.keys.grabs == 1 && rig.keys.grabbed == TriggerOverlay.gridKeys(.none))
    let first = OverlayGrid(cols: 4, rows: 2, at: Point(x: 100, y: 100), in: usableArea)
    #expect(rig.pickerGrid.shown == GridMark(grid: first, area: usableArea))
    rig.picker.key("move-right")
    rig.picker.key("grow-down")
    let span = first.moved(.right).grown(.down)
    #expect(rig.pickerGrid.shown == GridMark(grid: span, area: usableArea))
    rig.picker.key("return")
    #expect(rig.frame == span.frame(usableArea))
    #expect(!rig.picker.showing)
    #expect(rig.pickerGrid.shown == nil)
    #expect(rig.keys.ungrabs == 1 && rig.keys.grabbed.isEmpty)
}

// A drag across cells picks the span between the press and the release and fills it on release.
@Test func testGridDrag() {
    let rig = HoldRig()
    rig.at = Point(x: 100, y: 100)
    #expect(rig.picker.show(cols: 4, rows: 2, window: nil))
    rig.pickerGrid.mouse(.down, at: Point(x: 900, y: 100))
    rig.pickerGrid.mouse(.drag, at: Point(x: 2600, y: 100))
    let span = OverlayGrid(cols: 4, rows: 2, from: Point(x: 900, y: 100), to: Point(x: 2600, y: 100), in: usableArea)
    #expect(rig.pickerGrid.shown == GridMark(grid: span, area: usableArea))
    #expect(rig.moves == 0)
    rig.pickerGrid.mouse(.up, at: Point(x: 2600, y: 100))
    #expect(rig.frame == span.frame(usableArea))
    #expect(!rig.picker.showing)
}

// Escape puts the grid away and moves nothing.
@Test func testGridEscape() {
    let rig = HoldRig()
    #expect(rig.picker.show(cols: 4, rows: 2, window: nil))
    rig.picker.key("escape")
    #expect(!rig.picker.showing)
    #expect(rig.pickerGrid.shown == nil)
    #expect(rig.moves == 0)
}

// The grid starts at the window's middle when the pointer is off the area.
@Test func testGridStartOffArea() {
    let rig = HoldRig()
    rig.at = Point(x: 5000, y: 100)
    #expect(rig.picker.show(cols: 4, rows: 2, window: nil))
    let mid = Point(x: 1400 + 450, y: 300 + 350)
    #expect(rig.pickerGrid.shown?.grid == OverlayGrid(cols: 4, rows: 2, at: mid, in: usableArea))
}

// contains is true on the shown grid and false once it is put away.
@Test func testGridContains() {
    let rig = HoldRig()
    #expect(!rig.picker.contains(Point(x: 100, y: 100)))
    #expect(rig.picker.show(cols: 4, rows: 2, window: nil))
    #expect(rig.picker.contains(Point(x: 100, y: 100)))
    rig.picker.cancel()
    #expect(!rig.picker.contains(Point(x: 100, y: 100)))
}

// A pinned window, or no window at all, gets no grid.
@Test func testGridRefused() {
    let none = HoldRig()
    none.windows.focusedID = nil
    #expect(!none.picker.show(cols: 4, rows: 2, window: nil))
    #expect(none.logs == ["grid: no free window in front"])
    #expect(none.keys.grabs == 0)
    let pinned = HoldRig { $0.slots = [.leftTop: "com.example.pad"] }
    pinned.moor()
    #expect(pinned.anchors.pinned(pinned.windows.scan(pinned.screens.current(), full: true).windows[0]))
    #expect(!pinned.picker.show(cols: 4, rows: 2, window: nil))
}

// A window named by id gets the grid even when another is focused.
@Test func testGridNamedWindow() {
    let rig = HoldRig()
    let other = rig.windows.add(bundle: "com.example.other", frame: Frame(x: 100, y: 100, w: 400, h: 300), focus: true)
    rig.at = Point(x: 3000, y: 1000)
    #expect(rig.picker.show(cols: 2, rows: 1, window: rig.pad))
    rig.picker.key("return")
    #expect(rig.frame == Frame(x: 1720, y: 25, w: 1720, h: 1415))
    #expect(rig.windows.frame(other) == Frame(x: 100, y: 100, w: 400, h: 300))
}
