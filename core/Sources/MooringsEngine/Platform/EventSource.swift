// EventSource delivers what happens to windows and apps, so the engine wakes on events instead of
// polling.
public protocol EventSource: AnyObject {
    // start begins delivery; every window event reaches deliver on the engine's thread.
    func start(_ deliver: @escaping (WindowEvent) -> Void)
    // stop ends delivery.
    func stop()
    // waiting reports whether the source still waits on an app it was asked to watch.
    var waiting: Bool { get }
    // watch narrows the source to the apps in scan where the platform needs that (the Mac's per-app
    // AXObserver); Windows ignores it.
    func watch(_ scan: Scan)
}
