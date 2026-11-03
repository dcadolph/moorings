// EventSource delivers what happens to windows and apps, so the engine wakes on events instead of
// polling.
public protocol EventSource: AnyObject {
    // start begins delivery; every window event reaches deliver on the engine's thread.
    func start(_ deliver: @escaping (WindowEvent) -> Void)
    // stop ends delivery.
    func stop()
    // waiting reports whether the source still waits on an app it was asked to watch.
    var waiting: Bool { get }
    // watch runs after every pass with the windows it kept: the source watches their apps and their
    // closing where the platform needs that (the Mac's per-app AXObserver) and knows them as listed,
    // so an event for a window no pass listed can be filtered.
    func watch(_ scan: Scan)
    // quiet tells the source whether the engine is paused. A paused engine needs only a tick per
    // event, to find choices another program saved, so a quiet source may deliver a bare wake
    // instead of reading the window an event names.
    func quiet(_ on: Bool)
}

extension EventSource {
    // quiet does nothing: the source delivers the same events paused or not.
    public func quiet(_ on: Bool) {}
}
