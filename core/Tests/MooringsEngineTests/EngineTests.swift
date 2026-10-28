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
