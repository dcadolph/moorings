import MooringsCore
import MooringsEngine
import MooringsTesting

// HoldRig is the throw overlay, grid picker and hover mover on fakes over one 3440x1440 ultrawide with
// no slots, Right Option as the trigger, Control-Option to hover move and Control-Command to hover
// resize, and one free window focused.
final class HoldRig {
    // rightOption is Right Option's flags: its own device bit and the Option bit.
    static let rightOption: UInt64 = 0x40 | 0x80000
    // ctrlAlt is Control and Option held.
    static let ctrlAlt: UInt64 = 0x40000 | 0x80000
    // ctrlCmd is Control and Command held.
    static let ctrlCmd: UInt64 = 0x40000 | 0x100000

    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock.
    let clock = FakeClock()
    // footprint is the throw's preview.
    let footprint = FakeOverlay()
    // throwGrid draws the throw's keyboard grid.
    let throwGrid = FakeGrid()
    // pickerGrid draws the grid action's grid.
    let pickerGrid = FakeGrid()
    // throwTicks is the throw's scheduler.
    let throwTicks: FakeScheduler
    // hoverTicks is the hover's scheduler.
    let hoverTicks: FakeScheduler
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
    // at is where the pointer is.
    var at = Point(x: 0, y: 0)
    // down reports whether a mouse button is held.
    var down = false
    // under is the window the hit test finds, the pad by default.
    var under: WindowID?
    // shortcuts reports whether the shortcuts are on.
    var shortcuts = true
    // grabs lists every grab, by trigger.
    var grabs: [OverlayTrigger] = []
    // ungrabs counts the ungrabs.
    var ungrabs = 0
    // wakes counts the hover's wakes.
    var wakes = 0
    // logs lists every line logged.
    var logs: [String] = []

    // init builds the rig with choices changed by edit.
    init(_ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices(slots: [:])
        c.overlay.trigger = .rightOption
        c.overlay.hoverMove = [.ctrl, .alt]
        c.overlay.hoverResize = [.ctrl, .cmd]
        edit(&c)
        anchors = Anchors(choices: c)
        throwTicks = FakeScheduler(clock: clock)
        hoverTicks = FakeScheduler(clock: clock)
        let platform = Platform(
            windows: windows, screens: screens, overlay: FakeOverlay(), notifier: FakeNotifier(),
            clock: clock, scheduler: FakeScheduler(clock: clock), store: FakeStore(),
            warpCursor: { _ in })
        actions = ActionRunner(platform: platform, anchors: anchors)
        picker = GridPicker(platform: platform, anchors: anchors, actions: actions, view: pickerGrid)
        overlay = TriggerOverlay(
            platform: platform, anchors: anchors, actions: actions, footprint: footprint,
            gridView: throwGrid, picker: picker, ticker: throwTicks)
        hover = HoverMover(platform: platform, anchors: anchors, ticker: hoverTicks)
        pad = windows.add(bundle: "com.example.pad", frame: Frame(x: 1400, y: 300, w: 900, h: 700), focus: true)
        under = pad
        let rig = self
        overlay.pointer = { (rig.at, rig.down) }
        overlay.hit = { _ in rig.under }
        overlay.shortcutsOn = { rig.shortcuts }
        overlay.grab = { rig.grabs.append($0) }
        overlay.ungrab = { rig.ungrabs += 1 }
        overlay.log = { rig.logs.append($0) }
        picker.pointer = { rig.at }
        picker.grab = { rig.grabs.append($0) }
        picker.ungrab = { rig.ungrabs += 1 }
        picker.log = { rig.logs.append($0) }
        hover.pointer = { (rig.at, rig.down) }
        hover.hit = { _ in rig.under }
        hover.shortcutsOn = { rig.shortcuts }
        hover.wake = { rig.wakes += 1 }
        hover.log = { rig.logs.append($0) }
    }

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
        overlay.flagsChanged(0, at: at)
        hover.flagsChanged(0, at: at)
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
