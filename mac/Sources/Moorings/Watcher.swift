import AppKit
import ApplicationServices

// Watcher observes window events in each app that shows windows and calls its handler on each,
// so the poll runs fast while windows change.
@MainActor
final class Watcher {
    // events lists the app notifications that mean a window changed.
    private static let events = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    // handler runs on every event.
    private let handler: () -> Void
    // observers holds one observer per watched process.
    private var observers: [pid_t: AXObserver] = [:]

    // init builds a watcher that calls handler on each window event.
    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    // watch starts observing each process in pids not yet watched.
    func watch(_ pids: Set<pid_t>) {
        for pid in pids where observers[pid] == nil {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let watcher = Unmanaged<Watcher>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { watcher.handler() }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { continue }
            let app = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for event in Self.events {
                AXObserverAddNotification(observer, app, event as CFString, refcon)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        }
    }

    // forget stops observing a process that quit.
    func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
