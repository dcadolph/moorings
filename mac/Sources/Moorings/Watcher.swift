import AppKit
import ApplicationServices

import MooringsCore

// Watcher observes window events in each app and each window's close, and calls its handler on
// each, so passes run while windows change and stop once they are still.
@MainActor
final class Watcher {
    // events lists the app notifications that mean a window changed.
    private static let events = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]
    // tries is how many passes an app that is not ready for observers is asked again.
    private static let tries = 20

    // handler runs on every event with the element and the notification name.
    private let handler: (AXUIElement, String) -> Void
    // observers holds one observer per watched process.
    private var observers: [pid_t: AXObserver] = [:]
    // pending counts the tries left for processes whose window created event did not register,
    // which an app still starting up refuses.
    private var pending: [pid_t: Int] = [:]
    // closing holds the windows whose close is observed.
    private var closing: Set<WindowID> = []

    // init builds a watcher that calls handler on each window event.
    init(_ handler: @escaping (AXUIElement, String) -> Void) {
        self.handler = handler
    }

    // watch starts observing each process in pids not yet watched, and asks again of each one that
    // was not ready.
    func watch(_ pids: Set<pid_t>) {
        for pid in pids where observers[pid] == nil || pending[pid] != nil {
            guard let observer = observer(pid) else { continue }
            let app = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            var ready = true
            for event in Self.events {
                let err = AXObserverAddNotification(observer, app, event as CFString, refcon)
                if event == kAXWindowCreatedNotification, err != .success, err != .notificationAlreadyRegistered {
                    ready = false
                }
            }
            if ready {
                pending[pid] = nil
            } else {
                let left = (pending[pid] ?? Self.tries) - 1
                pending[pid] = left > 0 ? left : nil
            }
        }
    }

    // waiting reports whether an app has not yet taken its observer, so passes keep looking.
    var waiting: Bool { !pending.isEmpty }

    // watchClosing observes the close of each window in elements not yet observed, since a window
    // that closes behind the focused one sends no app notification.
    func watchClosing(_ elements: [WindowID: AXUIElement]) {
        closing.formIntersection(elements.keys)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (id, el) in elements where !closing.contains(id) {
            var pid: pid_t = 0
            guard AXUIElementGetPid(el, &pid) == .success, let observer = observer(pid) else { continue }
            let err = AXObserverAddNotification(observer, el, kAXUIElementDestroyedNotification as CFString, refcon)
            if err == .success || err == .notificationAlreadyRegistered {
                closing.insert(id)
            }
        }
    }

    // forget stops observing a process that quit.
    func forget(_ pid: pid_t) {
        pending[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    // observer returns the observer for pid, making it and adding it to the main run loop the
    // first time.
    private func observer(_ pid: pid_t) -> AXObserver? {
        if let observer = observers[pid] {
            return observer
        }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, el, note, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.handler(el, note as String) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        return observer
    }
}
