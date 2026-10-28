import WinSDK

import MooringsCore
import MooringsEngine

// WinEvents is the Windows EventSource: the out-of-context window event hooks of a WinWatcher. The
// hooks cover every process, so watch only marks the listed windows as top-level, and no app ever
// waits for an observer.
final class WinEvents: EventSource {
    // watcher holds the hooks while started, nil while stopped.
    private var watcher: WinWatcher?

    // waiting is false: the hooks need nothing from an app that just started.
    var waiting: Bool { false }

    // start installs the hooks and delivers each top-level window event to deliver.
    func start(_ deliver: @escaping (WindowEvent) -> Void) {
        stop()
        let w = WinWatcher { kind, hwnd in
            if let event = WinEvents.event(kind, WinWindows.id(hwnd)) {
                deliver(event)
            }
        }
        w.start()
        watcher = w
    }

    // stop removes the hooks.
    func stop() {
        watcher?.stop()
        watcher = nil
    }

    // watch marks each window in scan as top-level, so a window listed before its first event still
    // reports its destroy.
    func watch(_ scan: Scan) {
        for w in scan.windows {
            if let hwnd = WinWindows.hwnd(w.id) {
                watcher?.know(hwnd)
            }
        }
    }

    // event names the window event kind is for id, nil for a kind the engine does not hear.
    static func event(_ kind: WinEvent, _ id: WindowID) -> WindowEvent? {
        switch kind {
        case .show, .minimizeEnd: .shown(id)
        case .locationChange, .moveSizeEnd, .minimizeStart: .moved(id)
        case .foreground: .focused(id)
        case .destroy: .destroyed(id)
        case .moveSizeStart, .hide: nil
        }
    }
}
