import Foundation
import Testing

@testable import MooringsCore

// relativeNames lists the positions computed from the window's frame, which Geometry keeps private.
let relativeNames = [
    "maximize", "almost-maximize", "maximize-height", "center", "center-prominently", "move-left", "move-right",
    "move-up", "move-down", "move-top-left", "move-top-right", "move-bottom-left", "move-bottom-right",
    "larger-width", "smaller-width", "larger-height", "smaller-height", "double-width-left", "double-width-right",
    "double-height-up", "double-height-down", "halve-width-left", "halve-width-right", "halve-height-up",
    "halve-height-down",
]

// testGenReplays checks that the same seed makes the same cases, so a printed seed replays a failure.
@Test func testGenReplays() {
    var a = Gen(seed: 42)
    var b = Gen(seed: 42)
    let area = Frame(x: 0, y: 25, w: 5120, h: 1415)
    let one = (0..<Gen.cases).map { _ in a.frame(in: area) }
    let two = (0..<Gen.cases).map { _ in b.frame(in: area) }
    #expect(one == two)
    var c = Gen(seed: 43)
    #expect((0..<Gen.cases).map { _ in c.frame(in: area) } != one)
}

// Property: every named position, for any area, window and gap, lies inside its area.
@Test func testPropertyPositionInsideArea() {
    var g = Gen.seeded()
    let names = Array(Geometry.cells.keys).sorted() + relativeNames
    for name in relativeNames {
        #expect(Geometry.position(name, Frame(x: 0, y: 0, w: 1000, h: 800)) != nil, "unknown position \(name)")
    }
    for i in 0..<Gen.cases {
        let area = g.area()
        let cur = g.frame(in: area)
        let gap = g.double(0...20)
        let name = g.pick(names)
        guard let f = Geometry.position(name, area, cur, gap: gap) else { continue }
        #expect(within(f, area), "\(g.label(i)): \(name) in \(area) from \(cur) gap \(gap) gave \(f)")
    }
}

// Property: pressing a cycling action one more time than its cycle is long comes back to the first
// frame.
@Test func testPropertyCycleReturns() {
    var g = Gen.seeded()
    let names = Array(Geometry.cycles.keys).sorted()
    for i in 0..<Gen.cases {
        let area = g.area()
        let cur = g.frame(in: area)
        let gap = g.double(0...20)
        let name = g.pick(names)
        let n = Geometry.cycles[name]!.count
        let first = Geometry.cycle(name, 1, area, cur, gap: gap)
        let again = Geometry.cycle(name, n + 1, area, cur, gap: gap)
        #expect(
            first != nil && first == again,
            "\(g.label(i)): \(name) in \(area) gave \(String(describing: first)) then \(String(describing: again))")
    }
}

// Property: no sequence of arrow and grow keys takes the keyboard grid's span outside the grid or
// empties it.
@Test func testPropertyGridSpanStaysInside() {
    var g = Gen.seeded()
    let steps: [OverlayStep] = [.left, .right, .up, .down]
    for i in 0..<Gen.cases {
        let area = g.area()
        var grid = OverlayGrid(cols: g.int(1...16), rows: g.int(1...16), at: g.point(in: area), in: area)
        for _ in 0..<g.int(1...60) {
            let step = g.pick(steps)
            grid = g.bool() ? grid.moved(step) : grid.grown(step)
            let ok =
                0 <= grid.c0 && grid.c0 < grid.c1 && grid.c1 <= grid.cols && 0 <= grid.r0 && grid.r0 < grid.r1
                && grid.r1 <= grid.rows
            if !ok {
                Issue.record("\(g.label(i)): span \(grid) left a \(grid.cols) by \(grid.rows) grid")
                break
            }
        }
    }
}

// Property: a drop anywhere on a display that is not the ultrawide lands on a zone whose frame lies
// inside that display. Half the drops fall in the edge band, so every seed lands some.
@Test func testPropertyDropInsideScreen() {
    var g = Gen.seeded()
    var landed = 0
    for i in 0..<Gen.cases {
        let f = g.area()
        let p = g.bool() ? g.edgePoint(in: f, band: Snap.margin) : g.point(in: f)
        guard case let .zone(name)? = Snap.drop(SnapPoint(p.x, p.y), f) else { continue }
        guard let frame = Geometry.position(name, f) else {
            Issue.record("\(g.label(i)): drop at \(p) on \(f) named \(name), which has no frame")
            continue
        }
        landed += 1
        #expect(within(frame, f), "\(g.label(i)): drop at \(p) on \(f) gave \(name) at \(frame)")
    }
    #expect(landed > 0, "no drop landed on a zone")
}

// Property: over passes on random windows, a held pin stays inside its side's strip, and held windows
// of different apps never overlap.
@Test func testPropertyMoorKeepsPinsInStrips() {
    var g = Gen.seeded()
    let bundles = [slack, iterm, "com.apple.Notes", "com.apple.Safari", "com.google.Chrome"]
    let slots: [SlotKey] = [.leftTop, .leftBottom, .rightTop, .rightBottom]
    for i in 0..<Gen.cases {
        var map: [SlotKey: String] = [:]
        var free = bundles
        for slot in slots where g.bool() {
            map[slot] = free.remove(at: g.int(0...(free.count - 1)))
        }
        let anchors = Anchors(choices: Choices(slots: map))
        var world = TestWorld()
        for _ in 0..<g.int(1...6) {
            world.add(g.pick(bundles), g.frame(in: wide))
        }
        for _ in 0..<g.int(1...3) {
            world.pass(anchors)
            world.clock += 1
        }
        let ch = anchors.channel(wide)
        let held = world.windows.filter { anchors.held[$0.id] != nil }
        for w in held {
            guard let slot = map.first(where: { $0.value == w.bundle })?.key else { continue }
            let strip =
                slot.side == .left
                ? Frame(x: wide.x, y: wide.y, w: ch.x - wide.x, h: wide.h)
                : Frame(x: ch.x + ch.w, y: wide.y, w: wide.x + wide.w - ch.x - ch.w, h: wide.h)
            #expect(within(w.frame, strip), "\(g.label(i)): \(w.bundle) at \(w.frame) outside strip \(strip)")
        }
        for (j, a) in held.enumerated() {
            for b in held[(j + 1)...] where a.bundle != b.bundle {
                let overlap =
                    min(a.frame.x + a.frame.w, b.frame.x + b.frame.w) - max(a.frame.x, b.frame.x) > 1
                    && min(a.frame.y + a.frame.h, b.frame.y + b.frame.h) - max(a.frame.y, b.frame.y) > 1
                #expect(!overlap, "\(g.label(i)): \(a.bundle) at \(a.frame) overlaps \(b.bundle) at \(b.frame)")
            }
        }
    }
}
