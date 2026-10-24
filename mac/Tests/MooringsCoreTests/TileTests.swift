import Foundation
import Testing

@testable import MooringsCore

// tileChannel is the default channel of a 5120 by 1440 ultrawide.
let tileChannel = F(512, 25, 2304, 1415)

// covered returns the summed area of frames.
func covered(_ frames: [Frame]) -> Double {
    frames.reduce(0) { $0 + $1.w * $1.h }
}

// Lua case 0: Columns and rows split the area evenly with no gap.
@Test func testTileColumnsRows() {
    let c = Tile.columns(tileChannel, 3)
    #expect(c[0] == F(512, 25, 768, 1415))
    #expect(c[2] == F(2048, 25, 768, 1415))
    let r = Tile.rows(tileChannel, 2)
    #expect(r[0] == F(512, 25, 2304, 707))
    #expect(r[1] == F(512, 732, 2304, 708))
    #expect(Tile.columns(tileChannel, 1)[0] == tileChannel)
    #expect(Tile.columns(tileChannel, 0).isEmpty)
}

// Lua case 1: Columns with a gap leave the gap between and around them.
@Test func testTileColumnsGap() {
    let c = Tile.columns(tileChannel, 2, gap: 10)
    #expect(c[0] == F(522, 35, 1137, 1395))
    #expect(c[1].x - (c[0].x + c[0].w) == 10)
}

// Lua case 2: The grid is near square and a short last row widens to leave no hole.
@Test func testTileGrid() {
    for n in 1...10 {
        #expect(covered(Tile.grid(tileChannel, n)) == tileChannel.w * tileChannel.h)
    }
    let g = Tile.grid(tileChannel, 3)
    #expect(g[0] == F(512, 25, 1152, 707))
    #expect(g[1] == F(1664, 25, 1152, 707))
    #expect(g[2] == F(512, 732, 2304, 708))
    #expect(Tile.grid(tileChannel, 5)[3] == F(512, 732, 1152, 708))
    #expect(Tile.grid(tileChannel, 1)[0] == tileChannel)
}

// Lua case 3: Cascade steps each window and keeps sizes that fit.
@Test func testTileCascade() {
    let frames = Tile.cascade(tileChannel, [F(0, 0, 800, 600), F(0, 0, 900, 1415), F(0, 0, 3000, 500)], step: 30)
    #expect(frames[0] == F(512, 25, 800, 600))
    #expect(frames[1] == F(542, 55, 900, 1355))
    #expect(frames[2] == F(572, 85, 2244, 500))
    #expect(Tile.cascade(tileChannel, [F(9, 9, 800, 600)], step: 30)[0] == F(512, 25, 800, 600))
}

// Lua case 4: Many windows shrink the step so the stack stays within half the area.
@Test func testTileCascadeMany() {
    let list = Array(repeating: F(0, 0, 500, 400), count: 60)
    let frames = Tile.cascade(tileChannel, list, step: 30)
    #expect(frames[1].x - frames[0].x == 11)
    let last = frames[59]
    #expect(last.x + last.w <= tileChannel.x + tileChannel.w)
    #expect(last.y + last.h <= tileChannel.y + tileChannel.h)
}

// Lua case 5: Reverse mirrors across the area and twice is the identity.
@Test func testTileReverse() {
    let f = F(600, 100, 1000, 800)
    #expect(Tile.reverse(tileChannel, f) == F(1728, 100, 1000, 800))
    #expect(Tile.reverse(tileChannel, Tile.reverse(tileChannel, f)) == f)
    #expect(Tile.reverse(tileChannel, F(512, 25, 1152, 1415)) == F(1664, 25, 1152, 1415))
}

// Lua case 6: Every organize name is handled and others are not.
@Test func testTileNames() {
    for n in Tile.names {
        #expect(Tile.handles(n))
    }
    #expect(Tile.names.count == 9)
    #expect(!Tile.handles("left-half"))
}

// Lua has no case for the orders, tidy or the undo snapshot; these cover the ported functions.
@Test func testTileOrdersTidyUndo() {
    let a = TileWindow(id: 3, frame: F(100, 0, 10, 10))
    let b = TileWindow(id: 1, frame: F(100, 50, 10, 10))
    let c = TileWindow(id: 2, frame: F(0, 90, 10, 10))
    let d = TileWindow(id: 0, frame: F(100, 0, 10, 10))
    #expect([a, b, c, d].sorted(by: Tile.byX).map(\.id) == [2, 0, 3, 1])
    #expect([a, b, c, d].sorted(by: Tile.byY).map(\.id) == [0, 3, 1, 2])
    let t = Tile.tidy(tileChannel, [a, b, c, d], 3)
    #expect(t.map(\.0.id) == [2, 3, 1])
    #expect(t.map(\.1) == Tile.columns(tileChannel, 3))
    let undo = TileUndo.capture([a, c])
    #expect(undo.restore([2, 9, 3]).map(\.0) == [2, 3])
    #expect(undo.frames[2] == c.frame)
}

// Swift only: an overlapping frame shifts by the offset size, and a clear one stays put.
@Test func testOverlapOffsetShifts() {
    let area = F(0, 0, 1000, 800)
    let f = F(0, 0, 500, 400)
    #expect(Tile.overlapOffset(f, others: [F(0, 0, 300, 300)], area: area, size: 11, maxCascade: 1) == F(11, 11, 500, 400))
    #expect(Tile.overlapOffset(f, others: [F(200, 200, 300, 300)], area: area, size: 11, maxCascade: 1) == f)
    #expect(Tile.overlapOffset(f, others: [F(0, 0, 300, 300)], area: area, size: 0, maxCascade: 1) == f)
}

// Swift only: the cascade stops at max cascade steps, following stacked windows.
@Test func testOverlapOffsetCascade() {
    let area = F(0, 0, 1000, 800)
    let f = F(0, 0, 500, 400)
    let others = [F(0, 0, 300, 300), F(11, 11, 300, 300), F(22, 22, 300, 300)]
    #expect(Tile.overlapOffset(f, others: others, area: area, size: 11, maxCascade: 2) == F(22, 22, 500, 400))
    #expect(Tile.overlapOffset(f, others: others, area: area, size: 11, maxCascade: 5) == F(33, 33, 500, 400))
    #expect(Tile.overlapOffset(f, others: others, area: area, size: 11, maxCascade: 0) == f)
}

// Swift only: the offset never pushes a frame past the area's far edge, per axis.
@Test func testOverlapOffsetStaysInside() {
    let area = F(0, 0, 1000, 800)
    let full = F(0, 0, 1000, 800)
    #expect(Tile.overlapOffset(full, others: [full], area: area, size: 11, maxCascade: 3) == full)
    let wide = F(0, 0, 1000, 400)
    #expect(Tile.overlapOffset(wide, others: [wide], area: area, size: 11, maxCascade: 1) == F(0, 11, 1000, 400))
}
