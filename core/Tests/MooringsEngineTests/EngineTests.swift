import Foundation

import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// EngineRig is one Engine on fakes over one 3440x1440 ultrawide with one free window focused and the
// routed features given.
final class EngineRig {
    // routedNames lists one routed action of each feature: a grid, a stash, an organize, a tiling, a
    // workspace and a profile name.
    static let routedNames = [
        Overlay.gridName, "stash", "cycle-stacked-windows", "tiling-columns", "workspace:desk", "profile:work",
    ]

    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock.
    let clock = FakeClock(100)
    // log keeps every line logged.
    let log = FakeLog()
    // engine is the engine under test.
    let engine: Engine
    // pad is the free window, focused.
    let pad: WindowID

    // init builds the rig with features and choices changed by edit, with a workspace desk and a
    // profile work saved so their names are runnable.
    init(features: Engine.Features, _ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices(slots: [:])
        c.workspaces["desk"] = Workspace(name: "desk", slots: [:], widths: nil, heights: nil, windows: [], setup: nil)
        c.profiles = [Profile(name: "work", settings: c.profileSettings())]
        edit(&c)
        engine = newTestEngine(
            newTestPlatform(windows: windows, screens: screens, clock: clock, store: FakeStore(c), log: log),
            features: features)
        pad = windows.add(bundle: "com.example.pad", frame: Frame(x: 1400, y: 300, w: 900, h: 700), focus: true)
    }

    // actionLines lists the text of the lines logged under .actions.
    var actionLines: [String] { log.lines.filter { $0.category == .actions }.map(\.text) }
}

// Test 0: The routed names used below are routed and runnable on any platform.
@Test func testEngineRoutedNamesAreRouted() {
    let rig = EngineRig(features: .all)
    for name in EngineRig.routedNames {
        #expect(rig.engine.actions.routed(name), "\(name)")
        #expect(rig.engine.actions.runnable(name), "\(name)")
    }
}

// Test 1: An engine with no features supports none of the routed actions, runs none, and logs one
// actions line for each.
@Test func testEngineNoFeaturesRunsNoRouted() {
    let rig = EngineRig(features: [])
    for name in EngineRig.routedNames {
        #expect(!rig.engine.actions.supports(name), "\(name)")
        #expect(!rig.engine.actions.run(name), "\(name)")
    }
    #expect(rig.actionLines == EngineRig.routedNames.map { "\($0): not on this platform yet" })
}

// Test 2: An engine with every feature supports each routed action.
@Test func testEngineAllFeaturesSupportsRouted() {
    let rig = EngineRig(features: .all)
    for name in EngineRig.routedNames {
        #expect(rig.engine.actions.supports(name), "\(name)")
    }
}

// Test 3: Negative control: every feature but the stash supports every routed action but the stash.
@Test func testEngineWithoutStashDropsOnlyStash() {
    let rig = EngineRig(features: Engine.Features.all.subtracting(.stash))
    for name in EngineRig.routedNames {
        #expect(rig.engine.actions.supports(name) == (name != "stash"), "\(name)")
    }
}

// Test 4: A Command-drag dropped at the left edge stashes with the stash feature, and without it
// stashes nothing and drops as a plain drag does.
@Test func testEngineDragStashNeedsFeature() {
    for features in [Engine.Features.all, []] {
        let rig = EngineRig(features: features)
        let drag = rig.engine.drag
        drag.began(window: rig.pad, moving: true)
        rig.windows.nudge(rig.pad, to: Frame(x: 600, y: 300, w: 900, h: 700))
        drag.moved(Point(x: 0, y: 700), held: .command)
        drag.ended(held: .command)
        let stashed = !rig.engine.stasher.entries.isEmpty
        #expect(stashed == features.contains(.stash), "\(features)")
        #expect(rig.engine.anchors.stashed.isEmpty == !features.contains(.stash), "\(features)")
    }
}

// Test 5: One engine runs a pass that pins an anchored app, applies an action to the focused
// window, and follows a drag to the left half.
@Test func testEngineRunsPassActionAndDrag() {
    let rig = EngineRig(features: .all) { $0.slots = [.leftTop: "com.tinyspeck.slackmacgap"] }
    let slack = rig.windows.add(bundle: "com.tinyspeck.slackmacgap", frame: Frame(x: 1500, y: 200, w: 800, h: 600))
    rig.windows.focusedID = rig.pad
    var passes = 0
    rig.engine.observers.passed = { _, _ in passes += 1 }
    rig.engine.moor()
    #expect(passes == 1)
    let u = rig.screens.screens.usable[0]
    let ch = rig.engine.anchors.channel(u)
    #expect(near(rig.windows.frame(slack), Frame(x: u.x, y: u.y, w: ch.x - u.x, h: u.h)))
    #expect(rig.engine.actions.run("maximize"))
    #expect(near(rig.windows.frame(rig.pad), ch))
    var drops: [SnapDrop?] = []
    rig.engine.observers.dropped = { _, d in drops.append(d) }
    let dragged = Frame(x: ch.x + 10, y: 300, w: 900, h: 700)
    rig.engine.drag.began(window: rig.pad, moving: true)
    rig.windows.nudge(rig.pad, to: dragged)
    rig.engine.drag.moved(Point(x: 2, y: 700), held: [])
    rig.engine.drag.ended(held: [])
    #expect(drops.count == 1)
    #expect(drops.first.flatMap { $0 } != nil)
    #expect(rig.windows.frame(rig.pad) != dragged)
}

// Test 6: Negative control: an engine whose store is not ready runs no pass and moves nothing.
@Test func testEngineNotReadyMovesNothing() {
    let rig = EngineRig(features: .all) { $0.slots = [.leftTop: "com.tinyspeck.slackmacgap"] }
    let slack = rig.windows.add(bundle: "com.tinyspeck.slackmacgap", frame: Frame(x: 1500, y: 200, w: 800, h: 600))
    rig.windows.ready = false
    var passes = 0
    rig.engine.observers.passed = { _, _ in passes += 1 }
    rig.engine.start()
    rig.clock.advance(by: 2)
    #expect(passes == 0)
    #expect(rig.windows.frame(slack) == Frame(x: 1500, y: 200, w: 800, h: 600))
    #expect(!rig.engine.actions.run("maximize"))
}

// Test 7: Save writes the choices, binds the supported shortcuts, and logs the problems with the
// saved ones; a store that cannot write logs it and keeps the choices in effect.
@Test func testEngineSaveBindsSupported() throws {
    let store = FakeStore()
    let keys = FakeKeys()
    let log = FakeLog()
    let windows = FakeWindows()
    let engine = newTestEngine(
        newTestPlatform(
            windows: windows, screens: FakeScreens.ultrawide(), clock: FakeClock(), store: store, keys: keys,
            log: log),
        features: [])
    engine.anchors.choices.gapPx = 6
    engine.save()
    #expect(store.saved?.gapPx == 6)
    #expect(!keys.bound.isEmpty)
    #expect(keys.bound.keys.allSatisfy { engine.actions.supports($0) })
    #expect(keys.bound.keys.contains("left-half"))
    #expect(!keys.bound.keys.contains { engine.actions.routed($0) })
    store.failing = true
    engine.anchors.choices.gapPx = 8
    engine.save()
    #expect(log.lines.contains { $0.category == .choices && $0.text.hasPrefix("choices not saved") })
    #expect(engine.anchors.choices.gapPx == 8)
}

// Test 8: Reload reads the store's new choices and binds again.
@Test func testEngineReloadReadsStore() {
    let store = FakeStore()
    let keys = FakeKeys()
    let engine = newTestEngine(
        newTestPlatform(
            windows: FakeWindows(), screens: FakeScreens.ultrawide(), clock: FakeClock(), store: store, keys: keys))
    var c = Choices()
    c.gapPx = 12
    c.shortcuts["left-half"] = nil
    store.rewrite(c)
    engine.reload()
    #expect(engine.anchors.choices.gapPx == 12)
    #expect(keys.bound == Bindings(c).map.filter { engine.actions.supports($0.key) })
}

// Test 9: A full wake makes the next pass read every app, and a landed action wakes narrow.
@Test func testEngineWakesFullAndNarrow() {
    let rig = EngineRig(features: .all)
    rig.engine.moor()
    rig.clock.advance(by: Pace.settleSeconds + 1)
    rig.engine.passes.stop()
    rig.engine.landed(rig.pad, at: Frame(x: 1400, y: 300, w: 900, h: 700))
    #expect(rig.engine.passes.due != nil)
    var from = rig.windows.calls.count
    rig.engine.moor()
    #expect(rig.windows.calls.dropFirst(from).first == .scan(full: false))
    from = rig.windows.calls.count
    rig.engine.wake()
    rig.engine.moor()
    #expect(rig.windows.calls.dropFirst(from).first == .scan(full: true))
}

// Test 10: A grant between passes starts the events once and says Moorings is ready.
@Test func testEngineGrantStartsEvents() {
    let windows = FakeWindows()
    windows.ready = false
    let notifier = FakeNotifier()
    let platform = newTestPlatform(
        windows: windows, screens: FakeScreens.ultrawide(), clock: FakeClock(), notifier: notifier)
    let engine = newTestEngine(platform)
    let events = platform.events as! FakeEvents
    engine.moor()
    #expect(events.started == 0)
    windows.ready = true
    engine.moor()
    engine.moor()
    #expect(events.started == 1)
    #expect(notifier.notes.map(\.title) == ["Moorings is ready"])
    windows.ready = false
    engine.moor()
    #expect(events.stopped == 1)
}

// Test 11: Negative control: a store that could act all along starts nothing and says nothing.
@Test func testEngineSteadyReadyStartsNothing() {
    let notifier = FakeNotifier()
    let platform = newTestPlatform(
        windows: FakeWindows(), screens: FakeScreens.ultrawide(), clock: FakeClock(), notifier: notifier)
    let engine = newTestEngine(platform)
    let events = platform.events as! FakeEvents
    for _ in 0..<3 {
        engine.moor()
    }
    #expect(events.started == 0)
    #expect(events.stopped == 0)
    #expect(notifier.notes.isEmpty)
}

// Test 12: Choices another program wrote are read before the next pass and their shortcuts bound,
// once; a store that did not change reloads nothing.
@Test func testEngineReloadsChangedStore() {
    let store = FakeStore()
    let keys = FakeKeys()
    let log = FakeLog()
    let engine = newTestEngine(
        newTestPlatform(
            windows: FakeWindows(), screens: FakeScreens.ultrawide(), clock: FakeClock(), store: store, keys: keys,
            log: log))
    let reloads = { log.lines.filter { $0.category == .choices && $0.text == "choices reloaded" }.count }
    engine.moor()
    #expect(reloads() == 0)
    var c = Choices()
    c.gapPx = 14
    c.shortcuts["left-half"] = nil
    store.rewrite(c)
    engine.moor()
    #expect(engine.anchors.choices == c)
    #expect(keys.bound == Bindings(c).map.filter { engine.actions.supports($0.key) })
    #expect(reloads() == 1)
    engine.moor()
    #expect(reloads() == 1)
}

// Test 13: An app launch makes the scans read every app for Pace.launchSeconds, past the settle.
@Test func testEngineLaunchReadsEveryApp() {
    let rig = EngineRig(features: .all)
    rig.engine.start()
    rig.clock.advance(by: Pace.settleSeconds + 1)
    rig.windows.onEvent?(.appLaunched("com.example.new"))
    rig.clock.advance(by: Pace.settleSeconds + 1)
    rig.engine.passes.stop()
    var from = rig.windows.calls.count
    rig.engine.moor()
    #expect(rig.windows.calls.dropFirst(from).first == .scan(full: true))
    rig.clock.advance(by: Pace.launchSeconds)
    rig.engine.passes.stop()
    from = rig.windows.calls.count
    rig.engine.moor()
    #expect(rig.windows.calls.dropFirst(from).first == .scan(full: false))
}

// Test 14: Negative control: a move of a window no pass listed, after the windows settled, wakes
// exactly one narrow pass.
@Test func testEngineUnknownMoveWakesOnePass() {
    let rig = EngineRig(features: .all)
    rig.engine.start()
    rig.clock.advance(by: Pace.settleSeconds + 1)
    #expect(rig.engine.passes.due == nil)
    var passes = 0
    rig.engine.observers.passed = { _, _ in passes += 1 }
    var noticed: [WindowEvent] = []
    rig.engine.observers.noticed = { e, _ in noticed.append(e) }
    let from = rig.windows.calls.count
    rig.windows.onEvent?(.moved(999))
    rig.clock.advance(by: Pace.settleSeconds + 1)
    #expect(noticed == [.moved(999)])
    #expect(passes == 1)
    #expect(rig.windows.calls.dropFirst(from).first == .scan(full: false))
}

// Test 15: A store whose saved choices cannot be read starts the engine on the defaults and logs why
// under .choices, once.
@Test func testEngineLogsChoicesFallback() {
    let store = FakeStore()
    store.spoil(Data(#"{"gapPx":"#.utf8))
    let log = FakeLog()
    let windows = FakeWindows()
    let engine = newTestEngine(
        newTestPlatform(
            windows: windows, screens: FakeScreens.ultrawide(), clock: FakeClock(100), store: store, log: log))
    engine.start()
    let lines = log.lines.filter { $0.category == .choices }.map(\.text)
    #expect(lines.filter { $0.hasPrefix("choices fell back to the defaults: ") }.count == 1, "\(lines)")
    #expect(engine.anchors.choices == Choices())
    #expect(store.aside != nil)
}

// Test 16: Negative control: a store that reads its saved choices logs no fallback.
@Test func testEngineLogsNoFallbackForGoodChoices() {
    let log = FakeLog()
    let engine = newTestEngine(
        newTestPlatform(
            windows: FakeWindows(), screens: FakeScreens.ultrawide(), clock: FakeClock(100), store: FakeStore(),
            log: log))
    engine.start()
    #expect(!log.lines.contains { $0.text.hasPrefix("choices fell back") })
}

// fillRig returns an engine rig with a second free window and the focused one filling the channel,
// after a pass, and its fake keys.
private func fillRig(_ edit: (inout Choices) -> Void = { _ in }) -> (EngineRig, FakeKeys, WindowID) {
    let rig = EngineRig(features: .all, edit)
    let other = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 1500, y: 350, w: 700, h: 500))
    rig.windows.focusedID = rig.pad
    let s = rig.screens.current()
    let w = rig.windows.scan(s, full: true).windows.first { $0.id == rig.pad }!
    #expect(rig.engine.actions.fill(w, screens: s))
    rig.engine.moor()
    return (rig, rig.engine.platform.keys as! FakeKeys, other)
}

// Test 17: A pass with the focused window filling the channel claims Control-Left and Right, and
// with the switch off it never claims.
@Test func testEngineChannelCycleClaims() {
    let (rig, keys, _) = fillRig()
    #expect(rig.engine.channelCycle.claimed)
    #expect(keys.claimed == ChannelCycle.keys && keys.claims == 1)
    rig.engine.moor()
    #expect(keys.claims == 1, "a pass with nothing changed does not claim again")
    let (off, offKeys, _) = fillRig { $0.channelCycle = false }
    #expect(!off.engine.channelCycle.claimed && offKeys.claims == 0)
}

// Test 18: Shutdown lets the claimed keys go.
@Test func testEngineChannelCycleShutdown() {
    let (rig, keys, _) = fillRig()
    rig.engine.shutdown()
    #expect(!rig.engine.channelCycle.claimed && keys.claimed.isEmpty && keys.unclaims == 1)
}

// Test 19: A grab and an ungrab, as the throw overlay makes while its trigger key is held, leave the
// claim standing, and Control-Right then fills the channel with the other window and focuses it.
@Test func testEngineChannelCycleSurvivesGrab() {
    let (rig, keys, other) = fillRig()
    _ = keys.grab([GrabKey(key: "left", modifiers: [], tag: "throw-left")]) { _ in }
    keys.ungrab()
    #expect(keys.claimed == ChannelCycle.keys)
    let fill = rig.windows.frame(rig.pad)!
    keys.press(GrabKey(key: "right", modifiers: .control, tag: ""))
    #expect(rig.windows.focusedID == other)
    #expect(Actions.near(rig.windows.frame(other)!, fill, tolerance: 1))
}

// A pin moved by hand while paused stays where the owner put it, and goes back to its slot on
// resume, as Selftest's pause and resume checks expect.
@Test func testPausedPinMovedByHandGoesBackOnResume() {
    let rig = PassRig()
    rig.engine.listen()
    let id = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.passes.wake()
    rig.clock.advance(by: 3)
    #expect(near(rig.windows.frame(id), rig.slot))
    rig.anchors.choices.paused = true
    rig.engine.save()
    let moved = Frame(x: 900, y: 200, w: 700, h: 600)
    rig.windows.nudge(id, to: moved)
    rig.clock.advance(by: 3)
    #expect(rig.windows.frame(id) == moved)
    rig.anchors.choices.paused = false
    rig.engine.save()
    rig.clock.advance(by: 3)
    #expect(near(rig.windows.frame(id), rig.slot))
}

// A paused engine runs no pass for window events or the clock, and the first event after resume
// wakes passes again.
@Test func testPausedEngineRunsNoPasses() {
    let rig = PassRig()
    rig.engine.listen()
    var passes = 0
    rig.engine.observers.passed = { _, _ in passes += 1 }
    let id = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.passes.wake()
    rig.clock.advance(by: 3)
    rig.anchors.choices.paused = true
    rig.engine.save()
    passes = 0
    for i in 0..<5 {
        rig.windows.nudge(id, to: Frame(x: 1500 + Double(i) * 40, y: 200, w: 800, h: 600))
        rig.clock.advance(by: 0.5)
    }
    rig.clock.advance(by: 30)
    #expect(passes == 0)
    #expect(rig.scheduler.pendingAt == nil)
    rig.anchors.choices.paused = false
    rig.engine.save()
    passes = 0
    rig.windows.nudge(id, to: Frame(x: 1700, y: 200, w: 800, h: 600))
    rig.clock.advance(by: 1)
    #expect(passes > 0)
}

// A paused engine still reads choices another program saved when an event comes, so a resume
// written to the store wakes the passes.
@Test func testPausedEventReadsChoicesSavedElsewhere() {
    let rig = PassRig()
    rig.engine.listen()
    let store = rig.engine.platform.store as! FakeStore
    let id = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.anchors.choices.paused = true
    rig.engine.save()
    rig.windows.nudge(id, to: Frame(x: 1400, y: 200, w: 800, h: 600))
    rig.clock.advance(by: 3)
    #expect(!near(rig.windows.frame(id), rig.slot))
    var resumed = rig.anchors.choices
    resumed.paused = false
    store.rewrite(resumed)
    rig.windows.nudge(id, to: Frame(x: 1300, y: 200, w: 800, h: 600))
    rig.clock.advance(by: 3)
    #expect(!rig.anchors.choices.paused)
    #expect(near(rig.windows.frame(id), rig.slot))
}

// Pausing while an app launches, when passes run every Pace.busySeconds, still leaves no pass set.
@Test func testPausedWhileBusySetsNoPass() {
    let rig = PassRig()
    rig.engine.listen()
    var passes = 0
    rig.engine.observers.passed = { _, _ in passes += 1 }
    rig.engine.handle(.appLaunched("com.example.new"))
    rig.anchors.choices.paused = true
    rig.engine.save()
    passes = 0
    rig.clock.advance(by: Pace.launchSeconds / 2)
    #expect(passes == 0)
    #expect(rig.scheduler.pendingAt == nil)
}
