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
    // hit returns the window under p, in top-left coordinates, nil when no window is there.
    func hit(_ p: Point) -> WindowID?
    // title returns the window's title, nil when the window is gone or has none.
    func title(_ id: WindowID) -> String?
    // exitFullScreen asks the window to leave full screen; a platform without a full screen mode
    // does nothing.
    func exitFullScreen(_ id: WindowID)
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
