import Foundation

import MooringsCore
import MooringsEngine

// ScenarioFailure is one rule a scenario broke, with what was measured.
public struct ScenarioFailure: Equatable, Sendable, Codable, CustomStringConvertible {
    // scenario names the scenario that broke the rule.
    public var scenario: String
    // rule names the rule, with its limit.
    public var rule: String
    // detail says what was asked and what came back.
    public var detail: String

    // init builds a failure of rule in scenario.
    public init(scenario: String, rule: String, detail: String) {
        self.scenario = scenario
        self.rule = rule
        self.detail = detail
    }

    // description writes the failure on one line.
    public var description: String { "\(scenario): \(rule): \(detail)" }
}

// NamedFrame is a frame the report shows under a name.
public struct NamedFrame: Equatable, Sendable, Codable {
    // name says what the frame is.
    public var name: String
    // x is the left edge.
    public var x: Double
    // y is the top edge.
    public var y: Double
    // w is the width.
    public var w: Double
    // h is the height.
    public var h: Double

    // init names f.
    public init(_ name: String, _ f: Frame) {
        self.name = name
        x = f.x
        y = f.y
        w = f.w
        h = f.h
    }
}

// ScenarioResult is one scenario's run: the rules it broke, the frames it measured, and the picture
// the host took at its end.
public struct ScenarioResult: Equatable, Sendable, Codable {
    // name names the scenario.
    public var name: String
    // failures lists the rules it broke, empty when it passed.
    public var failures: [ScenarioFailure]
    // frames lists the frames it measured, in the order it measured them.
    public var frames: [NamedFrame]
    // notes lists the numbers it measured, one line each.
    public var notes: [String]
    // shot is where the host saved the picture, nil when it took none.
    public var shot: String?
    // seconds is how long it ran on the host's clock.
    public var seconds: Double

    // init builds a result.
    public init(
        name: String, failures: [ScenarioFailure], frames: [NamedFrame], notes: [String], shot: String?, seconds: Double
    ) {
        self.name = name
        self.failures = failures
        self.frames = frames
        self.notes = notes
        self.shot = shot
        self.seconds = seconds
    }

    // passed reports whether it broke no rule.
    public var passed: Bool { failures.isEmpty }
}

// Stage is one scenario's view of the engine and the host: it records what the engine's observers
// see, and collects the failures, frames and notes the report shows.
public final class Stage {
    // engine is the engine under test.
    public let engine: Engine
    // host opens, places and closes the windows and runs the platform while it waits.
    public let host: ScenarioHost
    // skew widens the strip the scenarios expect by this many points, their negative control.
    public let skew: Double
    // name names the scenario running.
    var name = ""
    // failures lists the rules broken so far.
    var failures: [ScenarioFailure] = []
    // frames lists the frames measured so far.
    var frames: [NamedFrame] = []
    // notes lists the numbers measured so far.
    var notes: [String] = []
    // moves lists each move a pass applied: the window and the time.
    var moves: [(id: WindowID, t: Double)] = []
    // releases lists each pin released by hand: the window and the time.
    var releases: [(id: WindowID, t: Double)] = []
    // passes lists the time of each pass.
    var passes: [Double] = []
    // events lists each window event the engine handled, and the time.
    var events: [(event: WindowEvent, t: Double)] = []

    // init builds a stage on engine and host whose expected strip is skew points wider.
    public init(engine: Engine, host: ScenarioHost, skew: Double = 0) {
        self.engine = engine
        self.host = host
        self.skew = skew
    }

    // fail records a broken rule.
    func fail(_ rule: String, _ detail: String) {
        failures.append(ScenarioFailure(scenario: name, rule: rule, detail: detail))
    }

    // note records a measured frame.
    func note(_ label: String, _ f: Frame?) {
        if let f {
            frames.append(NamedFrame(label, f))
        }
    }

    // measure records a measured number.
    func measure(_ line: String) {
        notes.append(line)
    }

    // frame reads the window's frame from the engine's store.
    func frame(_ id: WindowID) -> Frame? {
        engine.platform.windows.frame(id)
    }

    // wide returns the host's ultrawide, or records that it has none.
    func wide() -> Frame? {
        guard let wide = host.screens().wide else {
            fail("the host has an ultrawide", "none at the host's min aspect")
            return nil
        }
        return wide
    }

    // regions returns the strips and channel the pinned choices give on wide, the strip skew wider.
    func regions(_ wide: Frame) -> Regions {
        var r = Geometry.regions(wide, Scenarios.widths.left, Scenarios.widths.right)
        r.left.w += skew
        return r
    }

    // choose makes edit of the defaults the engine's choices and saves them, which binds the shortcuts
    // and runs a pass.
    func choose(_ edit: (inout Choices) -> Void) {
        var c = Choices()
        edit(&c)
        engine.anchors.choices = c
        engine.save()
    }

    // open opens a host window and waits until the store reads it, or records why it could not.
    func open(_ label: String) -> WindowInfo? {
        guard let id = host.open() else {
            fail("the host opens the \(label)", "none opened")
            return nil
        }
        let screens = host.screens()
        var found: WindowInfo?
        _ = host.wait(until: host.now + 2) {
            found = engine.platform.windows.scan(screens, full: true).windows.first { $0.id == id }
            return found != nil
        }
        if found == nil {
            fail("the store reads the \(label) within 2 s", "window \(id) never read")
        }
        return found
    }

    // place moves a window from outside the store, or records that the host could not.
    func place(_ id: WindowID, at f: Frame, _ label: String) -> Bool {
        guard host.place(id, at: f) else {
            fail("the host places the \(label)", "window \(id) not placed at \(f)")
            return false
        }
        return true
    }

    // hold runs the platform for seconds.
    func hold(_ seconds: Double) {
        _ = host.wait(until: host.now + seconds) { false }
    }

    // pin opens a window, pins its app to the left top slot with slot stacks off and the widths the
    // scenarios expect, and waits until it reads back at the left strip. It returns the window, the
    // strip and when the pass placed it, nil when any of that failed.
    func pin(paused: Bool = false) -> (pad: WindowInfo, strip: Frame, at: Double)? {
        guard let wide = wide(), let pad = open("pinned window") else { return nil }
        let strip = regions(wide).left
        note("strip", strip)
        let t0 = host.now
        choose {
            $0.slots = [.leftTop: pad.bundle]
            $0.widths = Scenarios.widths
            $0.slotStacks = false
            $0.paused = paused
        }
        guard !paused else { return (pad, strip, t0) }
        let placed = host.wait(until: t0 + Scenarios.placeSeconds) { Contract.near(frame(pad.id), strip) }
        note("pin", frame(pad.id))
        guard placed else {
            fail(
                "a pinned window reads back at its strip within 2 s, 1 point",
                "strip \(strip), pin \(Contract.show(frame(pad.id)))")
            return nil
        }
        let at = moves.last { $0.id == pad.id }?.t ?? host.now
        measure("pin placed \(Scenarios.seconds(at - t0)) s after the save")
        return (pad, strip, at)
    }

    // record points the engine's observers at the stage and returns what they were.
    func record() -> Engine.Observers {
        let saved = engine.observers
        engine.observers.moved = { [unowned self] move, t, _ in moves.append((move.id, t)) }
        engine.observers.released = { [unowned self] id, t in releases.append((id, t)) }
        engine.observers.passed = { [unowned self] t, _ in passes.append(t) }
        engine.observers.noticed = { [unowned self] event, t in events.append((event, t)) }
        return saved
    }

    // reset clears what one scenario recorded before the next.
    func reset(_ scenario: String) {
        name = scenario
        failures = []
        frames = []
        notes = []
        moves = []
        releases = []
        passes = []
        events = []
    }
}

// Scenarios runs the behavior every platform must show, as one function per scenario on any engine
// and host: the fakes, the Mac and Windows run the same steps with the same numbers.
public enum Scenarios {
    // widths are the strip widths the pass scenarios pin with, the moor probe's.
    static let widths = Widths(left: 40, right: 30)
    // placeSeconds is how soon a pinned window must read back at its strip.
    static let placeSeconds = 2.0
    // reactSeconds is how soon a pass must answer a window a person moved.
    static let reactSeconds = 1.0
    // graceSeconds is how long a scenario waits after a pin lands before moving it by hand, past the
    // core's 2 s release grace.
    static let graceSeconds = 3.0

    // all lists every scenario by name, in the order run runs them.
    public static let all: [(name: String, run: @Sendable (Stage) -> Void)] = [
        ("pinPlacesOnStrip", pinPlacesOnStrip),
        ("nudgedPinReleasesInGrace", nudgedPinReleasesInGrace),
        ("secondWindowGoesToChannel", secondWindowGoesToChannel),
        ("pausedMovesNothing", pausedMovesNothing),
        ("eventsWakeAndRestHolds", eventsWakeAndRestHolds),
    ]

    // run runs every scenario named in only, every one when only is empty, on engine and host, and
    // returns each result. The engine listens for window events while they run; its observers and
    // choices are put back after.
    public static func run(
        _ engine: Engine, host: ScenarioHost, only: Set<String> = [], skew: Double = 0
    ) -> [ScenarioResult] {
        let stage = Stage(engine: engine, host: host, skew: skew)
        let saved = stage.record()
        let choices = engine.anchors.choices
        engine.listen()
        defer {
            engine.platform.events.stop()
            engine.passes.stop()
            engine.observers = saved
            engine.anchors.choices = choices
        }
        var out: [ScenarioResult] = []
        for (name, scenario) in all where only.isEmpty || only.contains(name) {
            stage.reset(name)
            let t0 = host.now
            scenario(stage)
            let shot = host.shot(name)
            host.finish()
            stage.choose { _ in }
            out.append(
                ScenarioResult(
                    name: name, failures: stage.failures, frames: stage.frames, notes: stage.notes, shot: shot,
                    seconds: host.now - t0))
        }
        return out
    }

    // unknown lists the names in only that name no scenario.
    public static func unknown(_ only: Set<String>) -> [String] {
        only.subtracting(all.map(\.name)).sorted()
    }

    // seconds writes a span to the millisecond.
    static func seconds(_ s: Double) -> String {
        String(format: "%.3f", s)
    }
}
