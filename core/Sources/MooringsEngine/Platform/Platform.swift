// Platform bundles what the engine objects need from one platform. Each member is one capability
// with a fake and a contract.
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
    // store loads and saves choices.
    public var store: any ChoicesStore
    // pointer reads, moves and follows the mouse pointer.
    public var pointer: any Pointer
    // keys binds the shortcuts and grabs the keys a hold takes.
    public var keys: any Keys
    // apps names and opens apps.
    public var apps: any Apps
    // log records the engine's lines.
    public var log: any Log
    // timers hands each engine object its own scheduler.
    public var timers: any Timers
    // events delivers what happens to windows and apps.
    public var events: any EventSource
    // grid paints the grid action's grid and takes the mouse on it.
    public var grid: any GridView
    // badge paints the stack badge.
    public var badge: any BadgeView

    // init bundles a platform's parts.
    public init(
        windows: any WindowStore, screens: any ScreenSource, overlay: any OverlayView, notifier: any Notifier,
        clock: any Clock, store: any ChoicesStore, pointer: any Pointer, keys: any Keys, apps: any Apps,
        log: any Log, timers: any Timers, events: any EventSource, grid: any GridView, badge: any BadgeView
    ) {
        self.windows = windows
        self.screens = screens
        self.overlay = overlay
        self.notifier = notifier
        self.clock = clock
        self.store = store
        self.pointer = pointer
        self.keys = keys
        self.apps = apps
        self.log = log
        self.timers = timers
        self.events = events
        self.grid = grid
        self.badge = badge
    }
}
