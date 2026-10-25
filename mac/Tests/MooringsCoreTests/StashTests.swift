import Foundation
import Testing

@testable import MooringsCore

// stashArea is the usable area of a 1920 by 1080 display under a 25 point menu bar.
let stashArea = F(0, 25, 1920, 1055)

// Swift only: an edge another display touches cannot take a stash, and blocked edges drop out.
@Test func testStashEdges() {
    let main = F(0, 0, 1920, 1080)
    #expect(Stash.edges(main, others: []) == [.left, .right, .bottom])
    #expect(Stash.edges(main, others: [F(1920, 0, 2560, 1440)]) == [.left, .bottom])
    #expect(Stash.edges(main, others: [F(-1440, -200, 1440, 2560)]) == [.right, .bottom])
    #expect(Stash.edges(main, others: [F(200, 1080, 1920, 1080)]) == [.left, .right])
    #expect(Stash.edges(main, others: [F(1920, 2000, 800, 600)]) == [.left, .right, .bottom])
    #expect(Stash.edges(main, others: [], blocked: [.left, .right]) == [.bottom])
}

// Swift only: the nearest allowed edge takes the window, and none allowed means no stash.
@Test func testStashEdge() {
    #expect(Stash.edge(F(100, 300, 400, 300), area: stashArea, allowed: [.left, .right, .bottom]) == .left)
    #expect(Stash.edge(F(1400, 300, 400, 300), area: stashArea, allowed: [.left, .right, .bottom]) == .right)
    #expect(Stash.edge(F(760, 700, 400, 300), area: stashArea, allowed: [.left, .right, .bottom]) == .bottom)
    #expect(Stash.edge(F(100, 300, 400, 300), area: stashArea, allowed: [.right]) == .right)
    #expect(Stash.edge(F(100, 300, 400, 300), area: stashArea, allowed: []) == nil)
}

// Swift only: a stash parks the window with the sliver left on screen, slides out against the edge,
// and remembers where it was.
@Test func testStashFrames() throws {
    let w = F(100, 300, 400, 300)
    let left = try #require(Stash.stash(7, w, area: stashArea, allowed: [.left, .right, .bottom]))
    #expect(left.edge == .left && left.original == w && left.id == 7)
    #expect(left.shown == F(0, 300, 400, 300))
    #expect(left.hidden == F(-388, 300, 400, 300))
    #expect(Stash.sliverRect(left.hidden, screen: stashArea) == F(0, 300, 12, 300))
    let right = try #require(Stash.stash(7, F(1400, 300, 400, 300), area: stashArea, allowed: [.right]))
    #expect(right.shown == F(1520, 300, 400, 300))
    #expect(right.hidden == F(1908, 300, 400, 300))
    let bottom = try #require(Stash.stash(7, F(760, 700, 400, 300), area: stashArea, allowed: [.bottom]))
    #expect(bottom.shown == F(760, 780, 400, 300))
    #expect(bottom.hidden == F(760, 1068, 400, 300))
    let big = Stash.shown(F(-50, 0, 3000, 2000), .right, area: stashArea)
    #expect(big == stashArea)
    let spanned = Stash.shown(F(100, 700, 900, 300), .bottom, area: stashArea, span: F(512, 25, 896, 1055))
    #expect(spanned == F(512, 780, 896, 300))
}

// Swift only: a frame counts as parked only when most of it is off screen.
@Test func testStashParked() {
    #expect(Stash.parked(F(-388, 300, 400, 300), screen: stashArea))
    #expect(!Stash.parked(F(0, 300, 400, 300), screen: stashArea))
    #expect(!Stash.parked(F(-100, 300, 400, 300), screen: stashArea))
    #expect(Stash.parked(F(-400, 300, 400, 300), screen: stashArea))
    #expect(!Stash.parked(F(0, 0, 0, 0), screen: stashArea))
}

// Swift only: resting on the sliver for the rest time slides the window out, leaving it slides it
// back, and a pointer off the sliver or a held button does nothing.
@Test func testStashHover() throws {
    var s = try #require(Stash.stash(7, F(100, 300, 400, 300), area: stashArea, allowed: [.left]))
    let on = Point(x: 5, y: 400)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 10, mouseHeld: false) == .none)
    #expect(s.restSince == 10)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 10.1, mouseHeld: false) == .none)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 10.15, mouseHeld: false) == .slideOut)
    s.out = true
    #expect(Stash.hover(&s, Point(x: 300, y: 400), screen: stashArea, now: 11, mouseHeld: false) == .none)
    #expect(Stash.hover(&s, Point(x: 403, y: 400), screen: stashArea, now: 11, mouseHeld: false) == .none)
    #expect(Stash.hover(&s, Point(x: 410, y: 400), screen: stashArea, now: 11, mouseHeld: false) == .slideBack)
    s.out = false
    s.restSince = nil
    let below = Point(x: 5, y: 700)
    #expect(Stash.hover(&s, below, screen: stashArea, now: 12, mouseHeld: false) == .none)
    #expect(Stash.hover(&s, below, screen: stashArea, now: 13, mouseHeld: false) == .none)
    #expect(s.restSince == nil)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 14, mouseHeld: false) == .none)
    #expect(Stash.hover(&s, Point(x: 50, y: 400), screen: stashArea, now: 14.1, mouseHeld: false) == .none)
    #expect(s.restSince == nil)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 15, mouseHeld: true) == .none)
    #expect(Stash.hover(&s, on, screen: stashArea, now: 16, mouseHeld: true) == .none)
    #expect(s.restSince == nil)
}
