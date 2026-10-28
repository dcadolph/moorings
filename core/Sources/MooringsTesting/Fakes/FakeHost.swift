import Foundation

import MooringsCore
import MooringsEngine

// FakeHost is the ContractHost over FakeWindows and a FakeClock: its windows allow 300 by 200 at the
// least, and waiting advances the clock in 10 ms steps.
public final class FakeHost: ContractHost {
    // windows is the store the host opens windows in.
    public let windows: FakeWindows
    // clock is the clock waiting advances.
    public let clock: FakeClock
    // source holds the displays.
    private let source: FakeScreens
    // keys receives the presses the host makes, nil when the host makes none.
    public var keys: FakeKeys?
    // store is the store the host rewrites from outside, nil when it rewrites none.
    public var store: FakeStore?
    // drag is the follower the host's drags feed, nil when the host drags nothing.
    public var drag: DragFollower?
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
        let id = windows.add(
            bundle: "contract.host", frame: Frame(x: 600, y: 300, w: 800, h: 600), isMain: opened.isEmpty,
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

    // press hands the press to keys, when the host has them.
    public func press(_ key: GrabKey) -> Bool {
        guard let keys else { return false }
        keys.press(key)
        return true
    }

    // knownApp is the app FakeApps knows by default.
    public var knownApp: String? { "contract.host" }

    // nudge moves the window 10 points right outside the store.
    public func nudge(_ id: WindowID) -> Bool {
        guard var f = windows.frame(id) else { return false }
        f.x += 10
        windows.nudge(id, to: f)
        return true
    }

    // touchChoices rewrites store with a gap of 3, when the host has one.
    public func touchChoices() -> Bool {
        guard let store else { return false }
        var c = Choices()
        c.gapPx = 3
        store.rewrite(c)
        return true
    }

    // spoilChoices spoils store with payload, when the host has one.
    public func spoilChoices(_ payload: Data) -> Bool {
        guard let store else { return false }
        store.spoil(payload)
        return true
    }

    // choicesAside is what store moved aside, when the host has one.
    public func choicesAside() -> Data? {
        store?.aside
    }
}

extension FakeHost: ScenarioHost {
    // dragSteps is how many pointer moves a fake drag makes.
    static let dragSteps = 20

    // drag moves the window by offset the way a person drags it by the title bar: the follower hears
    // the press, then at each step the window and the pointer move together, the clock advances a
    // thirtieth of a second, and the follower hears the point with held; then it hears the release.
    public func drag(_ id: WindowID, by offset: Point, held: Modifiers) -> Bool {
        guard let drag, let start = windows.frame(id) else { return false }
        let grab = Scenarios.grab(start)
        drag.began(window: id, moving: true, at: grab)
        for i in 1...Self.dragSteps {
            let t = Double(i) / Double(Self.dragSteps)
            var f = start
            f.x += offset.x * t
            f.y += offset.y * t
            windows.nudge(id, to: f)
            clock.advance(by: 1.0 / 30)
            drag.moved(Point(x: grab.x + offset.x * t, y: grab.y + offset.y * t), held: held)
        }
        drag.ended(held: held)
        return true
    }

    // place moves the window to frame outside the store.
    public func place(_ id: WindowID, at frame: Frame) -> Bool {
        guard windows.frame(id) != nil else { return false }
        windows.nudge(id, to: frame)
        return true
    }
}
