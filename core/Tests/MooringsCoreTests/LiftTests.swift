import Foundation
import Testing

@testable import MooringsCore

// safari and notes are the extra bundles the lift scenarios use.
let safari = "com.apple.Safari"
let notes = "com.apple.Notes"
// vlc is the bundle of a player that resizes itself to its video.
let vlc = "org.videolan.vlc"

// LiftWorld holds windows that take moves the way real apps do: a window keeps its minimum size or
// its aspect ratio, leaves fullscreen when asked unless it is stuck, and reports its frame back
// after each move.
struct LiftWorld {
    // Windows lists the movable windows, front-most first.
    var windows: [WindowInfo] = []
    // MinSize holds the smallest size each window will take.
    var minSize: [WindowID: (w: Double, h: Double)] = [:]
    // Aspect holds the width over height each window keeps, its height following its width.
    var aspect: [WindowID: Double] = [:]
    // Late holds the frame a window reports once, on its next move, while still resizing itself.
    var late: [WindowID: Frame] = [:]
    // Midway holds the frame a window reports once, on its next move, while it animates on to the
    // frame it was given.
    var midway: [WindowID: Frame] = [:]
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
    // Unreadable holds the windows whose frame cannot be read back after a move, as with a busy app.
    var unreadable: Set<WindowID> = []

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

    // take applies frame to the window with id, kept at its minimum size and aspect ratio, and
    // returns where it landed.
    mutating func take(_ id: WindowID, _ frame: Frame) -> Frame {
        var got = late.removeValue(forKey: id) ?? frame
        if let m = minSize[id] {
            got.w = max(got.w, m.w)
            got.h = max(got.h, m.h)
        }
        if let a = aspect[id] {
            got.h = (got.w / a).rounded()
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
            var got = take(move.id, move.frame)
            if let m = midway.removeValue(forKey: move.id) {
                got = m
            }
            if unreadable.contains(move.id) {
                anchors.unread(move)
                continue
            }
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

// Test: With slotStacks off, a pinned app's other window in native fullscreen follows the free
// window rule, so it is turned into a channel fill only when fullscreenFills is on.
@Test func testLiftSecondWindowFullscreen() {
    for fills in [true, false] {
        var choices = Choices(slots: [.leftTop: slack, .rightTop: iterm])
        choices.slotStacks = false
        choices.fullscreenFills = fills
        let anchors = liftAnchors(choices)
        var world = LiftWorld()
        world.add(slack, Frame(x: 1000, y: 100, w: 900, h: 700))
        let huddle = world.add(slack, Frame(x: 1200, y: 200, w: 400, h: 300), main: false)
        world.pass(anchors)
        world.full(huddle, true)
        world.pass(anchors)
        #expect((world.exits[huddle] != nil) == fills)
    }
}

// Test: With slotStacks on, a pinned app's other window in native fullscreen follows the pin rule:
// it is asked to leave fullscreen and then returns to the slot.
@Test func testLiftSecondWindowFullscreenStacks() {
    var choices = Choices(slots: [.leftTop: slack, .rightTop: iterm])
    choices.fullscreenFills = false
    let anchors = liftAnchors(choices)
    var world = LiftWorld()
    let main = world.add(slack, Frame(x: 1000, y: 100, w: 900, h: 700))
    let huddle = world.add(slack, Frame(x: 1200, y: 200, w: 400, h: 300), main: false)
    world.pass(anchors)
    world.full(huddle, true)
    world.pass(anchors)
    #expect(world.exits[huddle] != nil)
    #expect(world.info(huddle).isFullScreen == false)
    world.pass(anchors)
    #expect(world.frame(huddle) == world.frame(main))
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
    #expect(anchors.floors[w] == Floor(w: 668, h: 0))
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

// Swift only: a pin read back partway through its own lift animation is not released when the
// animation ends where moorings put it, and a hand move from the lifted frame still releases it.
@Test func testLiftAnimationNoRelease() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let term = world.add(iterm, Frame(x: 3000, y: 100, w: 900, h: 700))
    world.pass(anchors)
    #expect(world.frame(term) == rightFull)
    world.clock += 3
    anchors.toggleLift(world.info(term))
    world.midway[term] = Frame(x: 2000, y: 25, w: 3120, h: 1415)
    world.pass(anchors)
    let lifted = Frame(x: 512, y: 25, w: 4608, h: 1415)
    #expect(world.frame(term) == lifted)
    for _ in 1...3 {
        world.clock += 3
        world.pass(anchors)
    }
    #expect(world.released.isEmpty)
    #expect(anchors.isLifted(term))
    #expect(world.frame(term) == lifted)
    #expect(anchors.readBack(term) == lifted)
    let moved = Frame(x: 1200, y: 200, w: 1800, h: 900)
    world.set(term, moved)
    world.pass(anchors)
    #expect(world.released == [term])
    #expect(world.frame(term) == moved)
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

// Swift only: a pin that will not shrink and could not be read back after its first move is placed
// again on the next pass and learns its floor, rather than being released as moved by hand.
@Test func testLiftUnreadNoRelease() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let w = world.add(slack, Frame(x: 300, y: 100, w: 900, h: 700))
    world.minSize[w] = (723, 0)
    world.unreadable = [w]
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 0, y: 25, w: 723, h: 1415))
    world.unreadable = []
    for _ in 1...3 {
        world.clock += 3
        world.pass(anchors)
    }
    #expect(world.released.isEmpty)
    #expect(!anchors.isReleased(w))
    #expect(anchors.floors[w] == Floor(w: 723, h: 0))
}

// Swift only: a player read back while it still resizes itself to its video learns no floor wider
// than the channel, so it ends inside the channel with its controls on screen, and a hand shrink
// holds.
@Test func testLiftFalseFloor() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let v = world.add(vlc, Frame(x: 1382, y: 156, w: 3705, h: 1390))
    world.aspect[v] = 16.0 / 9
    world.late[v] = Frame(x: 1382, y: 156, w: 3621, h: 1377)
    let ch = anchors.channel(wide)
    for _ in 1...3 {
        world.pass(anchors)
        world.clock += 5
    }
    #expect(Geometry.clamp(world.frame(v), ch) == world.frame(v))
    let shrunk = Frame(x: 1000, y: 200, w: 1600, h: 900)
    world.set(v, shrunk)
    for _ in 1...3 {
        world.pass(anchors)
        world.clock += 5
    }
    #expect(world.frame(v) == shrunk)
}

// Swift only: a drag near the edge two windows share finds it, front pair first, and only where
// they overlap along it.
@Test func testSharedEdgeFind() {
    let left = F(0, 0, 500, 800), right = F(502, 0, 500, 800), below = F(0, 803, 500, 200)
    let frames = [left, right, below]
    #expect(SharedEdges.find(at: Point(x: 501, y: 400), frames: frames) == SharedEdge(a: 0, b: 1, vertical: true))
    #expect(SharedEdges.find(at: Point(x: 495, y: 400), frames: frames) == SharedEdge(a: 0, b: 1, vertical: true))
    #expect(SharedEdges.find(at: Point(x: 520, y: 400), frames: frames) == nil)
    #expect(SharedEdges.find(at: Point(x: 250, y: 801), frames: frames) == SharedEdge(a: 0, b: 2, vertical: false))
    #expect(SharedEdges.find(at: Point(x: 750, y: 801), frames: frames) == nil)
    #expect(SharedEdges.find(at: Point(x: 501, y: 400), frames: [left, F(510, 0, 500, 800)]) == nil)
    #expect(SharedEdges.find(at: Point(x: 501, y: 400), frames: [right, left]) == SharedEdge(a: 1, b: 0, vertical: true))
}

// Swift only: moving a shared edge resizes both windows, keeps the space between them and both far
// edges, and stops at the minimum size.
@Test func testSharedEdgeResize() {
    let (a, b) = SharedEdges.resize(F(0, 0, 500, 800), F(504, 0, 500, 800), vertical: true, delta: 100)
    #expect(a == F(0, 0, 600, 800) && b == F(604, 0, 400, 800))
    let (c, d) = SharedEdges.resize(F(0, 0, 500, 800), F(504, 0, 500, 800), vertical: true, delta: -1000)
    #expect(c.w == SharedEdges.minimum && d.x + d.w == 1004)
    let (e, f) = SharedEdges.resize(F(0, 0, 500, 400), F(0, 400, 500, 400), vertical: false, delta: 1000)
    #expect(e.h == 800 - SharedEdges.minimum && f == F(0, 800 - SharedEdges.minimum, 500, SharedEdges.minimum))
}

// Swift only: the edge resize keys decode leniently and must be held exactly.
@Test func testEdgeResizeKeys() throws {
    let c = try JSONDecoder().decode(OverlayChoices.self, from: Data(#"{"edgeResize":["ctrl","alt","bogus"]}"#.utf8))
    #expect(c.edgeResize == [.ctrl, .alt])
    #expect(try JSONDecoder().decode(OverlayChoices.self, from: Data("{}".utf8)).edgeResize == [])
    #expect(Hover.holds(0x40000 | 0x80000, [.ctrl, .alt]))
    #expect(!Hover.holds(0x40000 | 0x80000 | 0x20000, [.ctrl, .alt]))
    #expect(!Hover.holds(0, []))
    #expect(!Hover.holds(0x20000, [.shift]))
}

// Swift only: a pin that refuses its strip's width while alone learns no height, so when a second
// app takes the side's other row, it moves into its own row and never covers that app.
@Test func testLiftFloorWidthOnly() {
    let anchors = liftAnchors()
    var world = LiftWorld()
    let s = world.add(slack, Frame(x: 900, y: 100, w: 800, h: 600))
    world.minSize[s] = (668, 300)
    world.add(iterm, Frame(x: 3000, y: 100, w: 800, h: 600))
    let f = world.add("com.apple.finder", Frame(x: 1000, y: 300, w: 900, h: 400))
    for _ in 0..<3 {
        world.pass(anchors)
        world.clock += 0.25
    }
    #expect(world.frame(s) == Frame(x: 0, y: 25, w: 668, h: 1415))
    world.clock += 5
    anchors.assign(.leftBottom, "com.apple.finder")
    for _ in 0..<4 {
        world.pass(anchors)
        world.clock += 0.25
    }
    #expect(world.frame(s).y + world.frame(s).h <= world.frame(f).y)
    #expect(world.frame(f).x == 0 && world.frame(f).w == 668)
    #expect(anchors.floors[s] == Floor(w: 668, h: 0))
}

// Swift only: a pin that refuses a height keeps it learned.
@Test func testLiftFloorHeight() {
    let anchors = liftAnchors(Choices(slots: [.leftTop: slack, .leftBottom: notes]))
    var world = LiftWorld()
    let s = world.add(slack, Frame(x: 900, y: 100, w: 400, h: 600))
    world.minSize[s] = (300, 900)
    world.add(notes, Frame(x: 1000, y: 300, w: 400, h: 400))
    for _ in 0..<3 {
        world.pass(anchors)
        world.clock += 0.25
    }
    #expect(anchors.floors[s] == Floor(w: 0, h: 900))
}
