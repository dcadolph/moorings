import MooringsCore
import MooringsEngine
import MooringsTesting

// newTestPlatform builds a Platform on fakes over windows, screens and clock, with a fresh fake for
// every part a test does not pass.
func newTestPlatform(
    windows: FakeWindows, screens: FakeScreens, clock: FakeClock, overlay: any OverlayView = FakeOverlay(),
    notifier: any Notifier = FakeNotifier(), store: any ChoicesStore = FakeStore(),
    pointer: any Pointer = FakePointer(), keys: any Keys = FakeKeys(), apps: (any Apps)? = nil,
    log: any Log = FakeLog(), timers: (any Timers)? = nil, grid: any GridView = FakeGrid(),
    badge: any BadgeView = FakeBadge()
) -> Platform {
    Platform(
        windows: windows, screens: screens, overlay: overlay, notifier: notifier, clock: clock, store: store,
        pointer: pointer, keys: keys, apps: apps ?? FakeApps(windows: windows), log: log,
        timers: timers ?? FakeTimers(clock: clock), events: FakeEvents(windows: windows), grid: grid, badge: badge)
}

// newTestEngine builds an Engine on platform with the routed actions in features, every one unless a
// test names fewer.
func newTestEngine(
    _ platform: Platform, features: Engine.Features = .all,
    platformActions: any PlatformActions = NoPlatformActions(), throwViews: ThrowViews? = nil
) -> Engine {
    Engine(platform: platform, features: features, platformActions: platformActions, throwViews: throwViews)
}

// TestPlatformActions is a PlatformActions that handles the names it is given and records each run.
final class TestPlatformActions: PlatformActions {
    // names lists the actions it handles.
    let names: Set<String>
    // ran lists the actions run, in order.
    private(set) var ran: [String] = []

    // init handles names.
    init(_ names: Set<String>) {
        self.names = names
    }

    // handles reports whether name is one of names.
    func handles(_ name: String) -> Bool {
        names.contains(name)
    }

    // run records name and reports whether it is one of names.
    func run(_ name: String, window: WindowID?) -> Bool {
        ran.append(name)
        return names.contains(name)
    }
}

// center returns the middle of f.
func center(_ f: Frame) -> Point {
    Point(x: f.x + f.w / 2, y: f.y + f.h / 2)
}

// HoldRig is the throw overlay, grid picker and hover mover on fakes over one 3440x1440 ultrawide with
// no slots, Right Option as the trigger, Control-Option to hover move and Control-Command to hover
// resize, and one free window focused.
final class HoldRig {
    // rightOption is Right Option held: its own right-hand bit and the Option bit.
    static let rightOption: Modifiers = [.rightOption, .option]
    // ctrlAlt is Control and Option held.
    static let ctrlAlt: Modifiers = [.control, .option]
    // ctrlCmd is Control and Command held.
    static let ctrlCmd: Modifiers = [.control, .command]

    // windows is the fake window store, whose hit test finds the window under the pointer.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock.
    let clock = FakeClock()
    // pointer is the fake pointer.
    let pointer = FakePointer(Point(x: 0, y: 0))
    // keys records the grabs and turns the shortcuts off.
    let keys = FakeKeys()
    // log keeps every line logged.
    let log = FakeLog()
    // footprint is the throw's preview.
    let footprint = FakeOverlay()
    // throwGrid draws the throw's keyboard grid.
    let throwGrid = FakeGrid()
    // pickerGrid draws the grid action's grid, the platform's grid.
    let pickerGrid = FakeGrid()
    // timers hands out the engine's schedulers, in the order Engine builds its objects: workspaces,
    // stasher, overlay, hover, passes, badge.
    let timers: FakeTimers
    // engine builds the objects under test on the fakes.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // actions is the action runner the throw and the grid apply through.
    let actions: ActionRunner
    // picker is the grid picker under test.
    let picker: GridPicker
    // overlay is the throw overlay under test.
    let overlay: TriggerOverlay
    // hover is the hover mover under test.
    let hover: HoverMover
    // pad is the free window, focused.
    let pad: WindowID

    // init builds the rig with choices changed by edit.
    init(_ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices(slots: [:])
        c.overlay.trigger = .rightOption
        c.overlay.hoverMove = [.ctrl, .alt]
        c.overlay.hoverResize = [.ctrl, .cmd]
        edit(&c)
        timers = FakeTimers(clock: clock)
        let platform = newTestPlatform(
            windows: windows, screens: screens, clock: clock, store: FakeStore(c), pointer: pointer, keys: keys,
            log: log, timers: timers, grid: pickerGrid)
        engine = newTestEngine(platform, throwViews: ThrowViews(footprint: footprint, grid: throwGrid))
        anchors = engine.anchors
        actions = engine.actions
        picker = engine.gridPicker
        overlay = engine.overlay
        hover = engine.hover
        pad = windows.add(bundle: "com.example.pad", frame: Frame(x: 1400, y: 300, w: 900, h: 700), focus: true)
    }

    // throwTicks is the throw overlay's scheduler.
    var throwTicks: FakeScheduler { timers.made[2] }

    // hoverTicks is the hover mover's scheduler.
    var hoverTicks: FakeScheduler { timers.made[3] }

    // at is where the pointer is.
    var at: Point {
        get { pointer.position }
        set { pointer.position = newValue }
    }

    // down reports whether a mouse button is held.
    var down: Bool {
        get { pointer.buttonDown }
        set { pointer.buttonDown = newValue }
    }

    // logs lists the text of every line logged.
    var logs: [String] { log.lines.map(\.text) }

    // press holds the throw trigger with the pointer at p and runs the first tick.
    func press(at p: Point) {
        at = p
        overlay.flagsChanged(Self.rightOption, at: p)
        clock.advance(by: 0)
    }

    // point moves the pointer to p and runs one tick.
    func point(_ p: Point) {
        at = p
        clock.advance(by: TriggerOverlay.tickSeconds)
    }

    // release lets every modifier go and runs what that schedules.
    func release() {
        overlay.flagsChanged([], at: at)
        hover.flagsChanged([], at: at)
        clock.advance(by: 0)
    }

    // moor runs one Anchors pass on the fake windows and applies its moves, so slotted apps pin.
    func moor() {
        clock.advance(by: 1)
        let s = screens.current()
        let scan = windows.scan(s, full: true)
        let moves = anchors.moor(
            Scene(screen: s.wide, windows: scan.windows, focused: scan.focused?.id, now: clock.now))
        for m in moves where !m.exitFullScreen {
            windows.move(m.id, to: m.frame, from: nil, behavior: Behaviors())
        }
    }

    // frame returns the pad's frame now.
    var frame: Frame {
        windows.frame(pad) ?? Frame(x: 0, y: 0, w: 0, h: 0)
    }

    // moves counts the store's moves and positions.
    var moves: Int {
        windows.calls.filter {
            switch $0 {
            case .move, .position, .resize: true
            default: false
            }
        }.count
    }
}
