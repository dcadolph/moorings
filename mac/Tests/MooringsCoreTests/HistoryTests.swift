import Foundation
import Testing

@testable import MooringsCore

// Test 0: Undo steps back through the recorded frames and redo steps forward again.
@Test func testHistoryUndoRedo() {
    var h = History()
    let a = F(0, 0, 100, 100), b = F(10, 0, 100, 100), c = F(20, 0, 100, 100)
    h.record(1, from: a)
    h.record(1, from: b)
    #expect(h.undo(1, current: c) == b)
    #expect(h.undo(1, current: b) == a)
    #expect(h.undo(1, current: a) == nil)
    #expect(h.redo(1, current: a) == b)
    #expect(h.redo(1, current: b) == c)
    #expect(h.redo(1, current: c) == nil)
    #expect(h.undo(1, current: c) == b)
}

// Test 1: A new move after an undo drops what redo had.
@Test func testHistoryNewMoveDropsRedo() {
    var h = History()
    h.record(1, from: F(0, 0, 100, 100))
    _ = h.undo(1, current: F(10, 0, 100, 100))
    h.record(1, from: F(0, 0, 100, 100))
    #expect(h.redo(1, current: F(30, 0, 100, 100)) == nil)
}

// Test 2: A repeat move from the same frame is recorded once, and windows keep separate histories.
@Test func testHistoryRepeatAndWindows() {
    var h = History()
    h.record(1, from: F(0, 0, 100, 100))
    h.record(1, from: F(0.5, 0, 100, 100))
    h.record(2, from: F(50, 50, 100, 100))
    #expect(h.undo(1, current: F(9, 9, 9, 9)) == F(0, 0, 100, 100))
    #expect(h.undo(1, current: F(0, 0, 100, 100)) == nil)
    #expect(h.undo(2, current: F(9, 9, 9, 9)) == F(50, 50, 100, 100))
    #expect(h.undo(3, current: F(9, 9, 9, 9)) == nil)
}

// Test 3: Each window keeps only the last depth frames, and only the most recent windows are kept.
@Test func testHistoryLimits() {
    var h = History()
    for k in 0..<(History.depth + 5) {
        h.record(1, from: F(Double(k * 10), 0, 100, 100))
    }
    var n = 0
    var cur = F(999, 0, 100, 100)
    while let f = h.undo(1, current: cur) {
        cur = f
        n += 1
    }
    #expect(n == History.depth)
    #expect(cur == F(50, 0, 100, 100))
    for id in 0..<WindowID(History.windows + 1) {
        h.record(100 + id, from: F(1, 1, 1, 1))
    }
    #expect(h.undo(100, current: F(0, 0, 9, 9)) == nil)
    #expect(h.undo(100 + WindowID(History.windows), current: F(0, 0, 9, 9)) == F(1, 1, 1, 1))
}

// Test 4: Every move moorings saves before goes into the window's history.
@Test func testHistoryFromSave() {
    let anchors = Anchors()
    let w = WindowInfo(id: 7, bundle: "com.apple.TextEdit", frame: F(100, 100, 400, 300), onUltrawide: true,
                       isMain: true, isFilePanel: false)
    anchors.save(w)
    var moved = w
    moved.frame = F(0, 0, 400, 300)
    anchors.save(moved)
    #expect(anchors.history.undo(7, current: F(5, 5, 5, 5)) == F(0, 0, 400, 300))
    #expect(anchors.history.undo(7, current: F(0, 0, 400, 300)) == F(100, 100, 400, 300))
}
