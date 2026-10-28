import MooringsCore

// WindowEvent is one thing an EventSource saw happen.
public enum WindowEvent: Equatable, Sendable {
    case moved(WindowID)
    case shown(WindowID)
    case destroyed(WindowID)
    case focused(WindowID)
    case appLaunched(String)
    case appQuit(String)
    case screensChanged
    // wake is something a pass should look at with no window named: sleep ended, an app activated,
    // hid or unhid, the space changed.
    case wake
}
