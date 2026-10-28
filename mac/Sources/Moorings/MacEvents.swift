import AppKit
import ApplicationServices

import MooringsCore
import MooringsEngine

// MacEvents is the Mac EventSource: each app's Accessibility observer through a Watcher, plus the
// workspace and screen notifications.
@MainActor
final class MacEvents: @preconcurrency EventSource {
    // shownNotes are the window notifications that mean a window appeared.
    private static let shownNotes: Set<String> = [kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification]
    // movedNotes are the window notifications that mean a window's place or size changed.
    private static let movedNotes: Set<String> = [
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
    ]
    // focusedNotes are the window notifications that mean another window took focus.
    private static let focusedNotes: Set<String> = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
    ]
    // wakeNotes are the workspace notifications that mean the Mac woke.
    private static let wakeNotes: Set<Notification.Name> = [
        NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
    ]

    // store reads the processes and elements of the windows a scan listed.
    private let store: Windows
    // watcher holds the Accessibility observers.
    private lazy var watcher = Watcher { [unowned self] el, note in axEvent(el, note) }
    // deliver receives each event while started, nil while stopped.
    private var deliver: ((WindowEvent) -> Void)?
    // ids maps each window element whose close is observed to its id, since a destroyed element no
    // longer names its window.
    private var ids: [AXUIElement: WindowID] = [:]
    // tokens holds the notification center observers added by start.
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    // init builds a source that reads windows through store.
    init(store: Windows) {
        self.store = store
    }

    // waiting reports whether an app is still in its eager tries to take its observer.
    var waiting: Bool { watcher.waiting }

    // start begins delivery to deliver and observes app launches, quits, wakes and screen changes.
    func start(_ deliver: @escaping (WindowEvent) -> Void) {
        stop()
        self.deliver = deliver
        let workspace = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names + Self.wakeNotes {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let bundle = app?.bundleIdentifier ?? ""
                let regular = app?.activationPolicy == .regular
                MainActor.assumeIsolated {
                    self?.workspaceEvent(name, pid: pid, bundle: bundle, regular: regular)
                }
            }
            tokens.append((workspace, token))
        }
        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver?(.screensChanged) }
        }
        tokens.append((NotificationCenter.default, screens))
    }

    // stop ends delivery and drops every observer, so a restart registers each app again.
    func stop() {
        deliver = nil
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens = []
        watcher.reset()
        ids = [:]
    }

    // watch observes the apps of the windows in scan and the close of each of those windows while
    // started, so a source that delivers nothing takes no observers.
    func watch(_ scan: Scan) {
        guard deliver != nil else { return }
        var pids: Set<pid_t> = []
        var elements: [WindowID: AXUIElement] = [:]
        for w in scan.windows {
            guard let pid = store.pid(w.id), let el = store.elements[w.id] else { continue }
            pids.insert(pid)
            elements[w.id] = el
        }
        watcher.watch(pids)
        for (id, el) in elements {
            watchClosing(id, el)
        }
    }

    // watchClosing observes the close of window id with element el and keeps its id for the event.
    private func watchClosing(_ id: WindowID, _ el: AXUIElement) {
        ids[el] = id
        watcher.watchClosing(id, el)
    }

    // axEvent turns one Accessibility notification into a window event. A window that appears has
    // its close observed at once.
    private func axEvent(_ el: AXUIElement, _ note: String) {
        guard let deliver else { return }
        if note == kAXUIElementDestroyedNotification {
            guard let id = ids.removeValue(forKey: el) ?? Windows.id(el) else { return }
            deliver(.destroyed(id))
            return
        }
        guard let id = Windows.id(el) else { return }
        if Self.shownNotes.contains(note) {
            watchClosing(id, el)
            deliver(.shown(id))
        } else if Self.movedNotes.contains(note) {
            deliver(.moved(id))
        } else if Self.focusedNotes.contains(note) {
            deliver(.focused(id))
        }
    }

    // workspaceEvent turns one workspace notification into an app or wake event, and watches a
    // regular app that launched or forgets one that quit. pid is nil when the note names no app.
    private func workspaceEvent(_ name: Notification.Name, pid: pid_t?, bundle: String, regular: Bool) {
        if Self.wakeNotes.contains(name) {
            deliver?(.wake)
            return
        }
        guard let pid else { return }
        if name == NSWorkspace.didLaunchApplicationNotification {
            if regular {
                watcher.watch([pid])
            }
            deliver?(.appLaunched(bundle))
        } else {
            watcher.forget(pid)
            deliver?(.appQuit(bundle))
        }
    }
}
