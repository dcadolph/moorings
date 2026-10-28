import MooringsCore
import MooringsEngine

// ContractFailure is one contract rule an adapter broke, with what was measured.
public struct ContractFailure: Equatable, Sendable, CustomStringConvertible {
    // rule names the rule, with its limit, as the design states it.
    public var rule: String
    // detail says what was asked and what came back.
    public var detail: String

    // init builds a failure.
    public init(rule: String, detail: String) {
        self.rule = rule
        self.detail = detail
    }

    // description writes the failure on one line.
    public var description: String { "\(rule): \(detail)" }
}

// ContractHost is what a contract suite cannot do through the protocol it checks: open and close
// plain windows of one app, tell the time, and run the platform while it waits.
public protocol ContractHost: AnyObject {
    // screens returns the displays the host's windows open on.
    func screens() -> Screens
    // open opens a plain window of the host's app and returns its id, nil when it cannot.
    func open() -> WindowID?
    // openRefusing opens a window that refuses every move, nil when the host has none.
    func openRefusing() -> WindowID?
    // minimum is the smallest size the host's windows allow, nil when the platform does not say.
    var minimum: (w: Double, h: Double)? { get }
    // now is the host's clock in seconds.
    var now: Double { get }
    // wait runs the platform until done returns true or the deadline passes, and reports done.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool
    // finish closes every window the host opened.
    func finish()
}

// Contract holds what the suites share.
enum Contract {
    // near reports whether two frames agree within one point on every edge.
    static func near(_ a: Frame?, _ b: Frame?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.w - b.w) <= 1 && abs(a.h - b.h) <= 1
    }

    // show writes a frame, or none, for a failure detail.
    static func show(_ f: Frame?) -> String {
        f.map { "\($0)" } ?? "none"
    }

    // focus opens a host window, raises it and waits until the store reads it focused, and returns
    // its id, or records why it could not.
    static func focus(_ store: WindowStore, _ host: ContractHost, _ out: inout [ContractFailure]) -> WindowID? {
        guard let id = host.open() else {
            out.append(ContractFailure(rule: "the host opens a window", detail: "none opened"))
            return nil
        }
        let screens = host.screens()
        _ = host.wait(until: host.now + 1) { store.scan(screens, full: true).windows.contains { $0.id == id } }
        store.raise(id)
        guard host.wait(until: host.now + 1, { store.scan(screens, full: true).focused?.id == id }) else {
            out.append(ContractFailure(rule: "raise makes the window focused within 1 s",
                                       detail: "focused \(store.scan(screens, full: true).focused.map { "\($0.id)" } ?? "none")"))
            return nil
        }
        return id
    }
}

// FakeHost is the ContractHost over FakeWindows and a FakeClock: its windows allow 300 by 200 at the
// least, and waiting advances the clock in 10 ms steps.
public final class FakeHost: ContractHost {
    // windows is the store the host opens windows in.
    public let windows: FakeWindows
    // clock is the clock waiting advances.
    public let clock: FakeClock
    // source holds the displays.
    private let source: FakeScreens
    // opened lists the windows the host opened.
    private var opened: [WindowID] = []

    // init builds a host on windows, clock and screens.
    public init(windows: FakeWindows, clock: FakeClock, screens: FakeScreens) {
        self.windows = windows
        self.clock = clock
        source = screens
    }

    // minimum is 300 by 200, the size every host window allows at the least.
    public var minimum: (w: Double, h: Double)? { (300, 200) }

    // now is the fake clock's time.
    public var now: Double { clock.now }

    // screens returns the fake displays.
    public func screens() -> Screens {
        source.current()
    }

    // open adds a host window, main only when it is the host's first.
    public func open() -> WindowID? {
        let id = windows.add(bundle: "contract.host", frame: Frame(x: 600, y: 300, w: 800, h: 600), isMain: opened.isEmpty,
                             minW: 300, minH: 200)
        opened.append(id)
        return id
    }

    // openRefusing adds a window that refuses every move.
    public func openRefusing() -> WindowID? {
        let id = windows.add(bundle: "contract.refusing", frame: Frame(x: 700, y: 400, w: 500, h: 400), refuses: true)
        opened.append(id)
        return id
    }

    // wait advances the clock in 10 ms steps until done or the deadline.
    public func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        while !done() {
            guard clock.now < deadline else { return false }
            clock.advance(to: min(deadline, clock.now + 0.01))
        }
        return true
    }

    // finish closes every window the host opened.
    public func finish() {
        for id in opened {
            windows.close(id)
        }
        opened = []
    }
}
