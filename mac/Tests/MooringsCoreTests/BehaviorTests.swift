import Foundation
import Testing

@testable import MooringsCore

private let behaviorScreen = Frame(x: 0, y: 0, w: 1000, h: 800)

// Swift only: no gaps and no stage leaves the area unchanged.
@Test func testEffectiveAreaDefault() {
    #expect(Behavior.effectiveArea(behaviorScreen, Behaviors()) == behaviorScreen)
}

// Swift only: each edge gap shrinks the area from its own side.
@Test func testEffectiveAreaEdgeGaps() {
    var b = Behaviors()
    b.screenEdgeGapTop = 10
    b.screenEdgeGapBottom = 20
    b.screenEdgeGapLeft = 30
    b.screenEdgeGapRight = 40
    #expect(Behavior.effectiveArea(behaviorScreen, b) == Frame(x: 30, y: 10, w: 930, h: 770))
}

// Swift only: the notch gap replaces the top gap on a notched display only when set.
@Test func testEffectiveAreaNotch() {
    var b = Behaviors()
    b.screenEdgeGapTop = 5
    #expect(Behavior.effectiveArea(behaviorScreen, b, hasNotch: true).y == 5)
    b.screenEdgeGapTopNotch = 0
    #expect(Behavior.effectiveArea(behaviorScreen, b, hasNotch: true).y == 0)
    #expect(Behavior.effectiveArea(behaviorScreen, b, hasNotch: false).y == 5)
}

// Swift only: gaps skip other displays when main only and skip maximize when it is turned off.
@Test func testEffectiveAreaGapScope() {
    var b = Behaviors()
    b.screenEdgeGapLeft = 10
    b.gapsOnMainOnly = true
    #expect(Behavior.effectiveArea(behaviorScreen, b, isMain: false) == behaviorScreen)
    #expect(Behavior.effectiveArea(behaviorScreen, b, isMain: true).x == 10)
    b.applyGapsToMaximize = false
    #expect(Behavior.effectiveArea(behaviorScreen, b, isMaximize: true) == behaviorScreen)
    #expect(Behavior.effectiveArea(behaviorScreen, b, isMaximize: false).x == 10)
}

// Swift only: the stage strip is reserved when active or always accounted for, on the chosen side.
@Test func testEffectiveAreaStage() {
    var b = Behaviors()
    #expect(Behavior.effectiveArea(behaviorScreen, b) == behaviorScreen)
    #expect(Behavior.effectiveArea(behaviorScreen, b, stageActive: true) == Frame(x: 190, y: 0, w: 810, h: 800))
    #expect(Behavior.effectiveArea(behaviorScreen, b, stageActive: true, stageOnRight: true)
        == Frame(x: 0, y: 0, w: 810, h: 800))
    b.alwaysAccountForStage = true
    #expect(Behavior.effectiveArea(behaviorScreen, b).w == 810)
}

// Swift only: the first press always places the window whatever the mode.
@Test func testRepeatOutcomeFirstPress() {
    for mode in SubsequentExecution.allCases {
        #expect(Behavior.repeatOutcome(mode, press: 1, displayIndex: 0, displayCount: 2, direction: 1) == .place)
    }
}

// Swift only: cycle sizes cycles and none stays put on a repeat.
@Test func testRepeatOutcomeSizesAndNone() {
    #expect(Behavior.repeatOutcome(.cycleSizes, press: 2, displayIndex: 0, displayCount: 1) == .cycleSize)
    #expect(Behavior.repeatOutcome(.none, press: 3, displayIndex: 0, displayCount: 2, direction: 1) == .place)
}

// Swift only: traverse moves a side action to the adjacent display and wraps past the last one.
@Test func testRepeatOutcomeTraverse() {
    let m = SubsequentExecution.traverseDisplays
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 2, direction: 1) == .moveToDisplay(1))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 1, displayCount: 2, direction: 1) == .moveToDisplay(0))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 1, displayCount: 2, direction: -1) == .moveToDisplay(0))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 3, direction: -1) == .moveToDisplay(2))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 1, direction: 1) == .place)
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 2) == .place)
}

// Swift only: traverse and cycle moves sides across displays, and cycles sizes where it would wrap,
// on one display, and on every other action.
@Test func testRepeatOutcomeTraverseAndCycle() {
    let m = SubsequentExecution.traverseAndCycle
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 2, direction: 1) == .moveToDisplay(1))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 1, displayCount: 2, direction: 1) == .cycleSize)
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 2, direction: -1) == .cycleSize)
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 1, direction: 1) == .cycleSize)
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 2) == .cycleSize)
}

// Swift only: cycle displays wraps around and does nothing on one display.
@Test func testRepeatOutcomeCycleDisplays() {
    let m = SubsequentExecution.cycleDisplays
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 1, displayCount: 3) == .moveToDisplay(2))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 2, displayCount: 3) == .moveToDisplay(0))
    #expect(Behavior.repeatOutcome(m, press: 2, displayIndex: 0, displayCount: 1) == .place)
}

// Swift only: quadrants cycle on corners and sizes elsewhere, and switch sides flips halves only.
@Test func testRepeatOutcomeQuadrantsAndSides() {
    let q = SubsequentExecution.cycleQuadrants
    #expect(Behavior.repeatOutcome(q, press: 2, displayIndex: 0, displayCount: 1, corner: true) == .cycleQuadrant)
    #expect(Behavior.repeatOutcome(q, press: 2, displayIndex: 0, displayCount: 1) == .cycleSize)
    let s = SubsequentExecution.switchSides
    #expect(Behavior.repeatOutcome(s, press: 2, displayIndex: 0, displayCount: 1, direction: -1) == .switchSide)
    #expect(Behavior.repeatOutcome(s, press: 2, displayIndex: 0, displayCount: 1, half: true) == .switchSide)
    #expect(Behavior.repeatOutcome(s, press: 2, displayIndex: 0, displayCount: 1) == .place)
}

// Swift only: Chromium browsers and their channels are known, and nothing else is.
@Test func testChromium() {
    #expect(Behavior.chromium("com.google.Chrome"))
    #expect(Behavior.chromium("com.google.Chrome.canary"))
    #expect(Behavior.chromium("company.thebrowser.Browser"))
    #expect(!Behavior.chromium("com.google.Chromecast"))
    #expect(!Behavior.chromium("com.tinyspeck.slackmacgap"))
    #expect(!Behavior.chromium(nil))
}

// Swift only: Enhanced UI comes back after a move except where the mode leaves it off, and
// automatic leaves it off for Chromium unless VoiceOver is on.
@Test func testEnhancedUIPolicy() {
    let chrome = "com.google.Chrome", slack = "com.tinyspeck.slackmacgap"
    #expect(Behavior.restoresEnhancedUI(.disableEnable, bundle: chrome, assistive: false))
    #expect(!Behavior.restoresEnhancedUI(.disableOnly, bundle: slack, assistive: false))
    #expect(!Behavior.restoresEnhancedUI(.frontmostDisable, bundle: slack, assistive: false))
    #expect(Behavior.restoresEnhancedUI(.automatic, bundle: slack, assistive: false))
    #expect(!Behavior.restoresEnhancedUI(.automatic, bundle: chrome, assistive: false))
    #expect(Behavior.restoresEnhancedUI(.automatic, bundle: chrome, assistive: true))
    #expect(Behavior.disablesEnhancedUIOnActivation(.frontmostDisable, bundle: slack, assistive: false))
    #expect(Behavior.disablesEnhancedUIOnActivation(.automatic, bundle: chrome, assistive: false))
    #expect(!Behavior.disablesEnhancedUIOnActivation(.automatic, bundle: chrome, assistive: true))
    #expect(!Behavior.disablesEnhancedUIOnActivation(.automatic, bundle: slack, assistive: false))
    #expect(!Behavior.disablesEnhancedUIOnActivation(.disableEnable, bundle: chrome, assistive: false))
}

// Swift only: unsnap restores the saved size only when enabled, snapped and different from the current size.
@Test func testUnsnapSize() {
    var b = Behaviors()
    let cur = Frame(x: 0, y: 0, w: 500, h: 800)
    let saved = (w: 300.0, h: 400.0)
    #expect(Behavior.unsnapSize(b, wasSnapped: true, saved: saved, current: cur)?.w == 300)
    #expect(Behavior.unsnapSize(b, wasSnapped: false, saved: saved, current: cur) == nil)
    #expect(Behavior.unsnapSize(b, wasSnapped: true, saved: nil, current: cur) == nil)
    #expect(Behavior.unsnapSize(b, wasSnapped: true, saved: (w: 500, h: 800), current: cur) == nil)
    b.unsnapRestore = false
    #expect(Behavior.unsnapSize(b, wasSnapped: true, saved: saved, current: cur) == nil)
}

// Swift only: a window counts as snapped while its size matches and it moved no farther than the cursor.
@Test func testSnapped() {
    let placed = Frame(x: 0, y: 0, w: 600, h: 800)
    #expect(Behavior.snapped(placed, start: placed, moved: 0))
    #expect(Behavior.snapped(placed, start: Frame(x: 5, y: 3, w: 600, h: 800), moved: 8))
    #expect(!Behavior.snapped(placed, start: Frame(x: 40, y: 0, w: 600, h: 800), moved: 8))
    #expect(!Behavior.snapped(placed, start: Frame(x: 0, y: 0, w: 500, h: 800), moved: 8))
    #expect(!Behavior.snapped(placed, start: Frame(x: 0, y: 0, w: 600, h: 700), moved: 8))
}

// Swift only: unsnap keeps the top left unless the cursor would fall off the narrower window.
@Test func testUnsnapFrame() {
    let cur = Frame(x: 100, y: 50, w: 1000, h: 800)
    let size = (w: 400.0, h: 300.0)
    #expect(Behavior.unsnapFrame(cur, size: size, grab: 200) == Frame(x: 100, y: 50, w: 400, h: 300))
    #expect(Behavior.unsnapFrame(cur, size: size, grab: 368) == Frame(x: 100, y: 50, w: 400, h: 300))
    #expect(Behavior.unsnapFrame(cur, size: size, grab: 800) == Frame(x: 532, y: 50, w: 400, h: 300))
    #expect(Behavior.unsnapFrame(cur, size: size, grab: 5000) == Frame(x: 700, y: 50, w: 400, h: 300))
    #expect(Behavior.unsnapFrame(cur, size: (w: 1200, h: 900), grab: 900) == Frame(x: 100, y: 50, w: 1200, h: 900))
}

// Swift only: the title bar is the band beside and below the green button, on a title bar role.
@Test func testOnTitleBar() {
    let window = Frame(x: 100, y: 100, w: 800, h: 600)
    let button = Frame(x: 148, y: 106, w: 16, h: 16)
    #expect(Behavior.onTitleBar(Point(x: 400, y: 110), window: window, button: button, role: "AXWindow"))
    #expect(Behavior.onTitleBar(Point(x: 400, y: 127), window: window, button: button, role: "AXToolbar"))
    #expect(!Behavior.onTitleBar(Point(x: 400, y: 128), window: window, button: button, role: "AXWindow"))
    #expect(!Behavior.onTitleBar(Point(x: 120, y: 110), window: window, button: button, role: "AXWindow"))
    #expect(!Behavior.onTitleBar(Point(x: 400, y: 110), window: window, button: button, role: "AXButton"))
    #expect(!Behavior.onTitleBar(Point(x: 400, y: 110), window: window, button: nil, role: "AXWindow"))
    #expect(!Behavior.onTitleBar(Point(x: 400, y: 110), window: window, button: button, role: nil))
    #expect(!Behavior.onTitleBar(Point(x: 950, y: 110), window: window, button: button, role: "AXWindow"))
}

// Swift only: a double-click restores a window its last maximize still holds, and maximizes otherwise.
@Test func testTitleBarAction() {
    let full = Frame(x: 0, y: 0, w: 1000, h: 800)
    #expect(Behavior.titleBarAction(last: nil, frame: full) == "maximize")
    #expect(Behavior.titleBarAction(last: LastPress(name: "maximize", press: 1, frame: full), frame: full) == "restore")
    #expect(Behavior.titleBarAction(last: LastPress(name: "left-half", press: 1, frame: full), frame: full)
        == "maximize")
    let moved = Frame(x: 50, y: 0, w: 1000, h: 800)
    #expect(Behavior.titleBarAction(last: LastPress(name: "maximize", press: 1, frame: full), frame: moved)
        == "maximize")
}
