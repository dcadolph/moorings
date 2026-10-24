import Foundation
import Testing

@testable import MooringsCore

// safari and notes are the extra bundles the lift scenarios use.
let safari = "com.apple.Safari"
let notes = "com.apple.Notes"

// LiftWorld holds windows that take moves the way real apps do: a window keeps its minimum size,
// leaves fullscreen when asked unless it is stuck, and reports its frame back after each move.
struct LiftWorld {
    // Windows lists the movable windows, front-most first.
    var windows: [WindowInfo] = []
    // MinSize holds the smallest size each window will take.
    var minSize: [WindowID: (w: Double, h: Double)] = [:]
    // Stuck holds the windows that ignore a request to leave fullscreen.
    var stuck: Set<WindowID> = []
    // Moves counts the frame changes each window was given.
    var moves: [WindowID: Int] = [:]
    // Exits counts the requests each window got to leave fullscreen.
    var exits: [WindowID: Int] = [:]
    // Released collects every window a pass released.
    var released: [WindowID] = []
    // Clock is the time in seconds the next pass sees.
    var clock = 1000.0
    // MouseHeld reports whether the primary button is down.
    var mouseHeld = false

    // add appends a window that reports a green button and returns its id.
    @discardableResult
    mutating func add(_ bundle: String, _ frame: Frame, main: Bool = true) -> WindowID {
        let id = WindowID(windows.count + 1)
        windows.append(WindowInfo(id: id, bundle: bundle, frame: frame, onUltrawide: true, isMain: main))
        return id
    }

    // frame returns the frame of the window with id.
    func frame(_ id: WindowID) -> Frame {
        windows.first { $0.id == id }!.frame
    }

    // info returns the window with id, its green button 52 points in and 6 down.
    func info(_ id: WindowID) -> WindowInfo {
        var w = windows.first { $0.id == id }!
        w.zoomRect = Frame(x: w.frame.x + 52, y: w.frame.y + 6, w: 14, h: 14)
        return w
    }

    // set puts the window with id at frame, as the owner would.
    mutating func set(_ id: WindowID, _ frame: Frame) {
        windows[windows.firstIndex { $0.id == id }!].frame = frame
    }

    // full puts the window with id in or out of native fullscreen.
    mutating func full(_ id: WindowID, _ on: Bool) {
        windows[windows.firstIndex { $0.id == id }!].isFullScreen = on
    }

    // remove closes the window with id.
    mutating func remove(_ id: WindowID) {
        windows.removeAll { $0.id == id }
    }

    // take applies frame to the window with id, kept at its minimum size, and returns where it landed.
    mutating func take(_ id: WindowID, _ frame: Frame) -> Frame {
        var got = frame
        if let m = minSize[id] {
            got.w = max(got.w, m.w)
            got.h = max(got.h, m.h)
        }
        set(id, got)
        moves[id, default: 0] += 1
        return got
    }

    // pass runs one moor pass and applies its moves, reading each frame back as the app does.
    mutating func pass(_ anchors: Anchors) {
        let scene = Scene(screen: wide, windows: windows.map { info($0.id) }, mouseHeld: mouseHeld, now: clock)
        for move in anchors.moor(scene) {
            if move.exitFullScreen {
                exits[move.id, default: 0] += 1
                if !stuck.contains(move.id) {
                    full(move.id, false)
                }
                continue
            }
            let got = take(move.id, move.frame)
            if let again = anchors.landed(move, got: got) {
                _ = take(again.id, again.frame)
            }
        }
        released += anchors.justReleased
    }

    // click asks anchors what a click at x, y on a green button does.
    func click(_ anchors: Anchors, _ x: Double, _ y: Double, option: Bool = false) -> ZoomAction? {
        anchors.zoomClick(Point(x: x, y: y), option: option, front: windows.map { ($0.id, $0.frame) })
    }
}

// liftAnchors returns Anchors with Slack on the left and iTerm on the right, both opening.
func liftAnchors(_ choices: Choices = Choices(slots: [.leftTop: slack, .rightTop: iterm])) -> Anchors {
    let anchors = Anchors(choices: choices)
    anchors.launch(now: 1000)
    return anchors
}

// Lua case 14: Native fullscreen on the ultrawide is turned into a channel fill.
@Test func testLiftFullscreenFills() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(safari, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    world.full(w, true)
    world.pass(anchors)
    #expect(world.info(w).isFullScreen == false)
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 512, y: 25, w: 2304, h: 1415))
}

// Lua case 15: Unticking Fullscreen fills the channel leaves native fullscreen alone.
@Test func testLiftFullscreenOff() {
    let anchors = liftAnchors()
    anchors.choices.fullscreenFills = false
    var world = LiftWorld()
    let w = world.add(safari, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.full(w, true)
    world.pass(anchors)
    #expect(world.info(w).isFullScreen == true)
    #expect(world.exits[w] == nil)
}

// Lua case 28: A fullscreen exit that never lands within 5 seconds is not filled later.
@Test func testLiftLateExitNotFilled() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(safari, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.full(w, true)
    world.pass(anchors)
    world.clock += 10
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 1000, y: 200, w: 800, h: 600))
}

// Lua case 128: A pinned window that goes native fullscreen leaves it and lands in its slot.
@Test func testLiftPinFullscreen() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    world.pass(anchors)
    #expect(world.frame(term) == rightFull)
    world.full(term, true)
    world.set(term, Frame(x: 0, y: 0, w: 5120, h: 1440))
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == false)
    world.set(term, rightFull)
    world.pass(anchors)
    #expect(world.frame(term) == rightFull)
}

// Lua case 129: Unticking the pin setting leaves a pinned window in native fullscreen.
@Test func testLiftPinFullscreenOff() {
    let anchors = liftAnchors()
    anchors.choices.pinFullscreenFills = false
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    world.pass(anchors)
    world.full(term, true)
    world.pass(anchors)
    world.clock += 10
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == true)
}

// Lua case 130: The pin and channel fullscreen settings work independently.
@Test func testLiftFullscreenSwitchesIndependent() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    let free = world.add(safari, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    anchors.choices.fullscreenFills = false
    world.full(term, true)
    world.full(free, true)
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == false)
    #expect(world.info(free).isFullScreen == true)
    world.full(free, false)
    anchors.choices.fullscreenFills = true
    anchors.choices.pinFullscreenFills = false
    world.clock += 10
    world.pass(anchors)
    world.full(term, true)
    world.full(free, true)
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == true)
    #expect(world.info(free).isFullScreen == false)
}

// Lua case 131: A pinned app's other window in native fullscreen is left alone.
@Test func testLiftSecondWindowFullscreen() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    world.add(slack, Frame(x: 1000, y: 100, w: 900, h: 700))
    let huddle = world.add(slack, Frame(x: 1200, y: 200, w: 400, h: 300), main: false)
    world.pass(anchors)
    world.full(huddle, true)
    world.pass(anchors)
    #expect(world.info(huddle).isFullScreen == true)
    #expect(world.moves[huddle] == nil && world.exits[huddle] == nil)
}

// Lua case 132: A pinned window still animating out of fullscreen is told to leave once.
@Test func testLiftExitAskedOnce() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    world.pass(anchors)
    world.stuck.insert(term)
    world.full(term, true)
    world.pass(anchors)
    world.pass(anchors)
    #expect(world.exits[term] == 1)
    world.clock += 10
    world.pass(anchors)
    #expect(world.exits[term] == 2)
}

// Lua case 133: A pinned window that lands in its slot and goes fullscreen again is redirected again.
@Test func testLiftFullscreenAgain() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    world.pass(anchors)
    world.full(term, true)
    world.pass(anchors)
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == false)
    world.full(term, true)
    world.pass(anchors)
    #expect(world.info(term).isFullScreen == false)
    #expect(world.exits[term] == 2)
}

// Lua case 134: The pin fullscreen setting survives a save and reload.
@Test func testLiftFullscreenChoiceSaved() throws {
    var choices = Choices()
    choices.pinFullscreenFills = false
    let back = Choices.decode(try Choices.encode(choices))
    #expect(back.pinFullscreenFills == false)
    #expect(back.fullscreenFills == true)
    #expect(Choices.decode(Data("{}".utf8)).pinFullscreenFills == true)
}

// Lua case 165: A left pin that will not shrink to the strip keeps its own width at the edge and
// is not moved again.
@Test func testLiftFloorLeft() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(slack, Frame(x: 300, y: 100, w: 900, h: 700))
    world.minSize[w] = (668, 0)
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 0, y: 25, w: 668, h: 1415))
    for _ in 1...8 {
        world.clock += 5
        world.pass(anchors)
    }
    #expect(world.moves[w] == 1)
    #expect(anchors.floors[w] == Floor(w: 668, h: 1415))
}

// Lua case 166: A right pin that will not shrink keeps its right edge on the screen edge.
@Test func testLiftFloorRight() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(iterm, Frame(x: 3000, y: 100, w: 900, h: 700))
    world.minSize[w] = (2500, 0)
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 2620, y: 25, w: 2500, h: 1415))
    world.clock += 5
    world.pass(anchors)
    #expect(world.moves[w] == 2)
}

// Lua case 167: A bottom row that will not shrink in height keeps its bottom edge.
@Test func testLiftFloorBottom() {
    let finder = "com.apple.finder"
    let anchors = liftAnchors(Choices(slots: [.leftTop: slack, .leftBottom: finder]))
    var world = LiftWorld()
    world.add(slack, leftFull)
    let w = world.add(finder, Frame(x: 1000, y: 100, w: 600, h: 400))
    world.minSize[w] = (0, 800)
    world.pass(anchors)
    let f = world.frame(w)
    #expect(f.x == 0 && f.w == 512 && f.h == 800 && f.y + f.h == 1440)
    let moves = world.moves[w]
    world.clock += 5
    world.pass(anchors)
    #expect(world.moves[w] == moves)
}

// Lua case 168: A learned minimum holds the strip open through width changes, and Re-moor now
// tries the chosen width again.
@Test func testLiftFloorHoldsStrip() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(slack, Frame(x: 300, y: 100, w: 900, h: 700))
    world.minSize[w] = (668, 0)
    world.pass(anchors)
    let moves = world.moves[w]
    anchors.setWidths(Widths(left: 11, right: 45))
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 0, y: 25, w: 668, h: 1415))
    #expect(world.moves[w] == moves)
    anchors.setWidths(Widths(left: 20, right: 45))
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 0, y: 25, w: 1024, h: 1415))
    world.minSize[w] = (400, 0)
    anchors.setWidths(Widths(left: 10, right: 45))
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 0, y: 25, w: 668, h: 1415))
    anchors.remoorNow()
    world.pass(anchors)
    #expect(world.frame(w) == leftFull)
}

// Lua case 169: What was learned goes when the window closes and on Re-moor now.
@Test func testLiftFloorForgotten() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(slack, Frame(x: 300, y: 100, w: 900, h: 700))
    world.minSize[w] = (668, 0)
    world.pass(anchors)
    let kept = world.windows
    world.remove(w)
    world.pass(anchors)
    world.windows = kept
    world.minSize[w] = nil
    world.pass(anchors)
    #expect(world.frame(w) == leftFull)
    world.minSize[w] = (668, 0)
    world.set(w, Frame(x: 300, y: 100, w: 900, h: 700))
    world.pass(anchors)
    world.minSize[w] = nil
    anchors.remoorNow()
    world.pass(anchors)
    #expect(world.frame(w) == leftFull)
}

// Lua case 170: A pin that will not shrink widens its strip, the channel starts after it, free
// windows stay out from under it, and nothing moves on later passes.
@Test func testLiftFloorWidensStrip() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, Frame(x: 300, y: 100, w: 900, h: 700))
    world.minSize[s] = (668, 0)
    let f = world.add(safari, Frame(x: 520, y: 100, w: 800, h: 600))
    world.pass(anchors)
    world.pass(anchors)
    #expect(abs(anchors.channel(wide).x - 668) <= 1)
    #expect(world.frame(f).x >= 668)
    let (sm, fm) = (world.moves[s], world.moves[f])
    for _ in 1...5 {
        world.clock += 5
        world.pass(anchors)
    }
    #expect(world.moves[s] == sm && world.moves[f] == fm)
    #expect(abs(anchors.slotFrame(wide, .leftTop).w - 668) <= 1)
    #expect(anchors.minBy[.left] == slack)
}

// Lua case 173: A pin moved by hand is released once, left where it was put, and re-moored by
// Restore and by Re-moor now.
@Test func testLiftReleaseByHand() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, leftFull)
    world.pass(anchors)
    let moved = Frame(x: 900, y: 200, w: 700, h: 600)
    let byHand = { (world: inout LiftWorld) in
        world.clock += 3
        world.pass(anchors)
        world.set(s, moved)
        world.pass(anchors)
    }
    byHand(&world)
    #expect(world.frame(s) == moved)
    #expect(world.released == [s])
    #expect(anchors.isReleased(s))
    world.clock += 10
    world.pass(anchors)
    #expect(world.frame(s) == moved)
    #expect(world.released == [s])
    anchors.remoor(s)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    byHand(&world)
    #expect(world.frame(s) == moved)
    anchors.remoorNow()
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
}

// Lua case 174: Width changes re-place a pin and never release it, and a pin settling on its own
// within the grace is put back.
@Test func testLiftNoReleaseOnWidths() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, leftFull)
    world.pass(anchors)
    world.clock += 3
    anchors.setWidths(Widths(left: 15, right: 40))
    world.pass(anchors)
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 768, h: 1415))
    world.clock += 1
    var f = world.frame(s)
    f.w = 900
    world.set(s, f)
    world.pass(anchors)
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 768, h: 1415))
    #expect(world.released.isEmpty)
}

// Lua case 175: Lifting a pin puts it over its strip and the channel at full height, stopping at
// the other strip, and lowers it again. Re-moor also lowers it.
@Test func testLiftLiftsAndLowers() {
    let anchors = liftAnchors(Choices(slots: [.leftTop: notes, .leftBottom: slack, .rightTop: iterm]))
    var world = LiftWorld()
    let n = world.add(notes, Frame(x: 600, y: 100, w: 500, h: 500))
    let s = world.add(slack, Frame(x: 700, y: 200, w: 500, h: 500))
    let term = world.add(iterm, Frame(x: 3000, y: 100, w: 900, h: 700))
    world.pass(anchors)
    let leftTop = anchors.slotFrame(wide, .leftTop)
    let leftBottom = anchors.slotFrame(wide, .leftBottom)
    #expect(world.frame(s) == leftBottom)
    #expect(anchors.toggleLift(world.info(s)))
    world.pass(anchors)
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 2816, h: 1415))
    world.clock += 5
    world.pass(anchors)
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 2816, h: 1415))
    #expect(world.frame(n) == leftTop)
    anchors.toggleLift(world.info(s))
    world.pass(anchors)
    #expect(world.frame(s) == leftBottom)
    anchors.toggleLift(world.info(term))
    world.pass(anchors)
    #expect(world.frame(term) == Frame(x: 512, y: 25, w: 4608, h: 1415))
    anchors.remoor(term)
    world.pass(anchors)
    #expect(world.frame(term) == rightFull)
    let free = world.add(safari, Frame(x: 900, y: 100, w: 500, h: 500))
    #expect(anchors.toggleLift(world.info(free)) == false)
}

// Lua case 177: A click on a pin's green button lifts it, a second click lowers it, clicks
// elsewhere pass, and nothing is handled while paused.
@Test func testLiftGreenButton() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, leftFull)
    world.pass(anchors)
    #expect(world.click(anchors, 60, 40) == .lift(s))
    anchors.toggleLift(id: s)
    world.pass(anchors)
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 2816, h: 1415))
    #expect(world.click(anchors, 300, 300) == nil)
    #expect(world.click(anchors, 60, 40) == .lower(s))
    anchors.toggleLift(id: s)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    anchors.choices.paused = true
    #expect(world.click(anchors, 60, 40) == nil)
}

// Lua case 178: Pins moved while paused or by a display change are re-moored, not released, and a
// closed pin leaves no release, lift or green button behind.
@Test func testLiftNoReleaseWhenPausedOrScreens() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, leftFull)
    world.pass(anchors)
    world.clock += 3
    world.pass(anchors)
    anchors.choices.paused = true
    world.pass(anchors)
    world.set(s, Frame(x: 900, y: 200, w: 700, h: 600))
    world.clock += 3
    anchors.choices.paused = false
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    world.clock += 3
    world.pass(anchors)
    world.set(s, Frame(x: 900, y: 200, w: 700, h: 600))
    anchors.screensChanged()
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(world.released.isEmpty)
    anchors.toggleLift(id: s)
    let kept = world.windows
    world.remove(s)
    world.pass(anchors)
    #expect(world.click(anchors, 60, 40) == nil)
    world.windows = kept
    world.set(s, leftFull)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(!anchors.isLifted(s))
}

// Lua case 181: A pin released by a move it did not make keeps its green button, and a click
// there re-moors it.
@Test func testLiftReleasedGreenButton() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, leftFull)
    world.pass(anchors)
    world.clock += 3
    world.pass(anchors)
    #expect(world.click(anchors, 60, 40) == .lift(s))
    anchors.toggleLift(id: s)
    world.pass(anchors)
    world.clock += 3
    world.pass(anchors)
    world.set(s, Frame(x: 0, y: 25, w: 5120, h: 1415))
    world.pass(anchors)
    #expect(anchors.isReleased(s))
    #expect(world.click(anchors, 60, 40) == .remoor(s))
    anchors.remoor(s)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
}

// Lua case 195: A free window's green button fills the channel, a second click puts it back, and an
// Option-click or the fill turned off passes the click on.
@Test func testLiftFreeGreenButton() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let start = Frame(x: 1000, y: 200, w: 800, h: 600)
    let f = world.add(safari, start)
    world.pass(anchors)
    #expect(world.click(anchors, 1060, 215, option: true) == nil)
    #expect(world.click(anchors, 1060, 215) == .fill(f))
    anchors.save(world.info(f))
    world.set(f, anchors.channel(wide))
    anchors.markFilled(f, world.frame(f), from: start)
    world.pass(anchors)
    #expect(world.click(anchors, 570, 40) == .restore(f))
    world.set(f, anchors.unfill(f)!)
    #expect(world.frame(f) == start)
    #expect(!anchors.canUndo)
    world.pass(anchors)
    anchors.choices.fullscreenFills = false
    #expect(world.click(anchors, 1060, 215) == nil)
}

// Swift only: a window in front of a green button keeps the click.
@Test func testLiftCovered() {
    let p = Point(x: 60, y: 40)
    let cover: (id: WindowID, frame: Frame) = (1, Frame(x: 0, y: 0, w: 100, h: 100))
    let away: (id: WindowID, frame: Frame) = (1, Frame(x: 500, y: 500, w: 10, h: 10))
    let pin: (id: WindowID, frame: Frame) = (2, leftFull)
    #expect(Anchors.covered(2, p, front: [cover, pin]))
    #expect(!Anchors.covered(2, p, front: [pin, cover]))
    #expect(!Anchors.covered(2, p, front: [away, pin]))
}

// Swift only: a green fill-back after Tile puts the window back in its tile, not where it was before
// the tile, and Undo still returns it to where it was before the tile.
@Test func testLiftFillBackAfterTile() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let start = Frame(x: 1000, y: 200, w: 800, h: 600)
    let f = world.add(safari, start)
    world.pass(anchors)
    anchors.save(world.info(f))
    let tiled = Frame(x: 512, y: 25, w: 1152, h: 1415)
    world.set(f, tiled)
    world.pass(anchors)
    #expect(world.click(anchors, 564, 31) == .fill(f))
    anchors.save(world.info(f))
    world.set(f, anchors.channel(wide))
    anchors.markFilled(f, world.frame(f), from: tiled)
    world.pass(anchors)
    #expect(world.click(anchors, 564, 31) == .restore(f))
    world.set(f, anchors.unfill(f)!)
    #expect(world.frame(f) == tiled)
    #expect(anchors.unfill(f) == nil)
    #expect(anchors.undo() == [f: start])
}
