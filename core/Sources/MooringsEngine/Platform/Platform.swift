import MooringsCore

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
