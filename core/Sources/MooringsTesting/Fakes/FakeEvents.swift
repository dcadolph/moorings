import MooringsCore
import MooringsEngine

// FakeEvents is an EventSource over FakeWindows: every change to a fake window is delivered at once
// while it runs.
public final class FakeEvents: EventSource {
    // waiting reports whether the source waits on an app; tests set it.
    public var waiting = false
    // watched counts the scans the source was asked to watch.
    public private(set) var watched = 0
    // started counts the starts.
    public private(set) var started = 0
    // stopped counts the stops.
    public private(set) var stopped = 0
    // windows is the store whose changes are delivered.
    private let windows: FakeWindows

    // init builds a source over windows.
    public init(windows: FakeWindows) {
        self.windows = windows
    }

    // start delivers each change to deliver until stop.
    public func start(_ deliver: @escaping (WindowEvent) -> Void) {
        started += 1
        windows.onEvent = deliver
    }

    // stop ends delivery.
    public func stop() {
        stopped += 1
        windows.onEvent = nil
    }

    // watch counts the scan; fake windows need no narrowing.
    public func watch(_ scan: Scan) {
        watched += 1
    }
}
