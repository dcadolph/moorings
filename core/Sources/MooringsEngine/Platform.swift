import MooringsCore

// WindowStore reads and moves the windows of one platform. The engine decides where a window goes;
// the store only reports and obeys.
public protocol WindowStore: AnyObject {
    // scan lists the windows on screens, front to back, with the focused one. full reads every
    // app; otherwise the adapter may read only the apps that changed since its last scan.
    func scan(_ screens: Screens, full: Bool) -> Scan
    // frame returns the window's current frame, nil when it cannot be read.
    func frame(_ id: WindowID) -> Frame?
    // move places the window; from is its last read frame when known so an adapter can animate
    // or correct an invisible border. The adapter returns once the window answered, moved or not.
    func move(_ id: WindowID, to frame: Frame, from: Frame?, behavior: Behaviors)
    // resize sets the window's size and keeps its top-left corner.
    func resize(_ id: WindowID, w: Double, h: Double)
    // raise brings the window to the front and focuses it.
    func raise(_ id: WindowID)
    // minimize sends the window to the Dock or the taskbar.
    func minimize(_ id: WindowID)
    // close asks the window to close.
    func close(_ id: WindowID)
    // position moves the window's top-left corner to x, y and keeps its size.
    func position(_ id: WindowID, x: Double, y: Double)
    // refused lists the windows that refused a move this session (elevated on Windows, a
    // sandboxed or unmovable window on the Mac) so the engine never retries them.
    var refused: Set<WindowID> { get }
    // alive lists the ids that still exist, for pruning.
    func alive() -> Set<WindowID>
    // ready reports whether the store may act at all (AX trust on the Mac, always on Windows).
    var ready: Bool { get }
}

extension WindowStore {
    // position moves the window to x, y at the size it has now, for a store with no cheaper way.
    public func position(_ id: WindowID, x: Double, y: Double) {
        guard let f = frame(id) else { return }
        move(id, to: Frame(x: x, y: y, w: f.w, h: f.h), from: nil, behavior: Behaviors())
    }
}

// Scan is one read of the windows on screen.
public struct Scan: Sendable, Equatable {
    // windows lists the windows front to back.
    public var windows: [WindowInfo]
    // focused is the focused window, nil when none is.
    public var focused: WindowInfo?

    // init builds a scan from its windows and the focused one.
    public init(windows: [WindowInfo], focused: WindowInfo?) {
        self.windows = windows
        self.focused = focused
    }
}

// ScreenSource reads the attached displays.
public protocol ScreenSource: AnyObject {
    // current returns the attached displays.
    func current() -> Screens
    // quirks is what ActionTarget needs beyond frames: notched screens, Stage Manager strips.
    // Windows returns .none.
    func quirks(_ screens: Screens) -> ScreenQuirks
    // displaySetKey names the set of displays in screens, the same whatever order they come in, so a
    // workspace can be tied to it.
    func displaySetKey(_ screens: Screens) -> String
}

extension ScreenSource {
    // displaySetKey keys the displays by their full frames, which is what the Mac uses.
    public func displaySetKey(_ screens: Screens) -> String {
        Workspaces.signature(screens.full)
    }
}

// OverlayView paints the footprint that shows where a window will land.
public protocol OverlayView: AnyObject {
    // show paints the footprint at frame; a second show moves it.
    func show(_ frame: Frame, style: FootprintStyle, palette: Palette)
    // hide takes the footprint off screen.
    func hide()
    // shown is the frame the footprint covers, nil when hidden.
    var shown: Frame? { get }
}

// BadgeMark is what a stack badge shows: the count and the front window it sits on.
public struct BadgeMark: Equatable, Sendable {
    // count is the number of windows in the stack.
    public var count: Int
    // front is the frame of the stack's front window, whose top-right corner holds the badge.
    public var front: Frame

    // init builds a mark.
    public init(count: Int, front: Frame) {
        self.count = count
        self.front = front
    }
}

// BadgeView paints the stack badge, the count at the top-right corner of a stack's front window.
public protocol BadgeView: AnyObject {
    // show paints count at the top-right corner of front; a second show moves it.
    func show(_ count: Int, at front: Frame, palette: Palette)
    // hide takes the badge off screen.
    func hide()
    // shown is the mark the badge paints, nil when hidden.
    var shown: BadgeMark? { get }
}

// GridMark is what a grid overlay shows: the grid with its picked span and the area it divides.
public struct GridMark: Equatable, Sendable {
    // grid is the grid and its picked span.
    public var grid: OverlayGrid
    // area is the area the grid divides.
    public var area: Frame

    // init builds a mark.
    public init(grid: OverlayGrid, area: Frame) {
        self.grid = grid
        self.area = area
    }
}

// GridMouse is what the mouse did on a grid that takes clicks.
public enum GridMouse: Sendable {
    case down, drag, up
}

// GridView paints the cells an area is divided into, with the picked span filled, without taking
// focus. A grid with a mouse handler takes the presses, drags and releases on it; one without lets
// every click through.
public protocol GridView: AnyObject {
    // onMouse is told each press, drag and release on the grid with the pointer in top-left
    // coordinates, nil when the grid lets clicks through. It is set before the first show.
    var onMouse: ((GridMouse, Point) -> Void)? { get set }
    // show paints grid over area with its span inset by gap; a second show repaints it.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette)
    // hide takes the grid off screen.
    func hide()
    // shown is the mark the grid paints, nil when hidden.
    var shown: GridMark? { get }
    // contains reports whether p, in top-left coordinates, is on the shown grid.
    func contains(_ p: Point) -> Bool
}

// Notifier shows a short message without taking focus.
public protocol Notifier: AnyObject {
    // notify shows title and body.
    func notify(_ title: String, _ body: String)
}

// Clock tells the time the engine schedules against.
public protocol Clock: AnyObject {
    // now is seconds on a monotonic clock shared with the adapter's own timestamps.
    var now: Double { get }
}

// Scheduler runs one piece of deferred work on the engine's thread.
public protocol Scheduler: AnyObject {
    // schedule runs work at time at on the engine's thread, replacing any pending work.
    func schedule(at: Double, _ work: @escaping () -> Void)
    // cancel drops the pending work.
    func cancel()
}

// ChoicesStore loads and saves the user's choices.
public protocol ChoicesStore: AnyObject {
    // load returns the saved choices, or the defaults when none are saved.
    func load() -> Choices
    // save writes choices.
    func save(_ choices: Choices) throws
}

// Platform bundles what the engine objects need from one platform.
public struct Platform {
    // windows reads and moves windows.
    public var windows: any WindowStore
    // screens reads the displays.
    public var screens: any ScreenSource
    // overlay paints the drag footprint.
    public var overlay: any OverlayView
    // notifier shows messages.
    public var notifier: any Notifier
    // clock tells the time.
    public var clock: any Clock
    // scheduler runs deferred work.
    public var scheduler: any Scheduler
    // store loads and saves choices.
    public var store: any ChoicesStore
    // warpCursor moves the pointer to a point.
    public var warpCursor: (Point) -> Void

    // init bundles a platform's parts.
    public init(
        windows: any WindowStore, screens: any ScreenSource, overlay: any OverlayView, notifier: any Notifier,
        clock: any Clock, scheduler: any Scheduler, store: any ChoicesStore, warpCursor: @escaping (Point) -> Void
    ) {
        self.windows = windows
        self.screens = screens
        self.overlay = overlay
        self.notifier = notifier
        self.clock = clock
        self.scheduler = scheduler
        self.store = store
        self.warpCursor = warpCursor
    }
}
