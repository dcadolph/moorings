import Foundation

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
    // press synthesizes a press of key and reports whether the host could; a rule that needs a press
    // skips with one printed line on a host that cannot.
    func press(_ key: GrabKey) -> Bool
    // knownApp is the bundle id of an app the host can open and name, nil when it has none.
    var knownApp: String? { get }
    // nudge moves the window a little from outside the store, the way a person would, and reports
    // whether the host could.
    func nudge(_ id: WindowID) -> Bool
    // touchChoices rewrites the saved choices from outside the store, as another program would, and
    // reports whether the host could.
    func touchChoices() -> Bool
    // spoilChoices writes payload where the store keeps the saved choices, as a damaged disk or a hand
    // edit would, and reports whether the host could.
    func spoilChoices(_ payload: Data) -> Bool
    // choicesAside returns what the store moved aside, nil when nothing is there or the host cannot
    // look.
    func choicesAside() -> Data?
}

extension ContractHost {
    // press reports that the host cannot synthesize a press.
    public func press(_ key: GrabKey) -> Bool {
        false
    }

    // knownApp is nil for a host with no app to open.
    public var knownApp: String? { nil }

    // nudge reports that the host cannot move a window from outside the store.
    public func nudge(_ id: WindowID) -> Bool {
        false
    }

    // touchChoices reports that the host cannot rewrite the saved choices.
    public func touchChoices() -> Bool {
        false
    }

    // spoilChoices reports that the host cannot write a payload.
    public func spoilChoices(_ payload: Data) -> Bool {
        false
    }

    // choicesAside is nil for a host that cannot look.
    public func choicesAside() -> Data? {
        nil
    }
}

// Contract holds what the suites share.
enum Contract {
    // near reports whether two frames agree within one point on every edge.
    static func near(_ a: Frame?, _ b: Frame?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.w - b.w) <= 1 && abs(a.h - b.h) <= 1
    }

    // skip prints the one line a rule writes when the host cannot run it.
    static func skip(_ rule: String, _ why: String) {
        print("contract skipped: \(rule): \(why)")
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
            out.append(
                ContractFailure(
                    rule: "raise makes the window focused within 1 s",
                    detail: "focused \(store.scan(screens, full: true).focused.map { "\($0.id)" } ?? "none")"))
            return nil
        }
        return id
    }
}
