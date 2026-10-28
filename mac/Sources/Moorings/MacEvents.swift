import AppKit
import ApplicationServices

import MooringsCore
import MooringsEngine

// MacEvents is the Mac EventSource: each app's Accessibility observer through a Watcher, the
// workspace and screen notifications, and the mouse tap kept alive beside them. It drops the events
// no pass acts on and marks the app a kept event names, so the next scan reads only that app.
@MainActor
final class MacEvents: @preconcurrency EventSource {
    // shownNotes are the window notifications that mean a window appeared.
    private static let shownNotes: Set<String> = [kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification]
    // movedNotes are the window notifications that mean a window's place or size changed.
    private static let movedNotes: Set<String> = [
        kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowMiniaturizedNotification,
    ]
    // echoNotes are the window notifications a placement's own move sends.
    private static let echoNotes: Set<String> = [kAXWindowMovedNotification, kAXWindowResizedNotification]
    // focusedNotes are the window notifications that mean another window took focus.
    private static let focusedNotes: Set<String> = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
    ]
    // wakeNotes are the workspace notifications that mean a pass should look with no window named:
    // the Mac woke, an app came forward, hid or unhid, or the space changed.
    private static let wakeNotes: Set<Notification.Name> = [
        NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
        NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
    ]

    // turned is told each start and stop, for the menu bar icon's warning mark.
    var turned: () -> Void = {}

    // store reads the processes and elements of the windows a scan listed and keeps the app marks.
    private let store: Windows
    // tap is the mouse tap the source starts, stops and re-arms, nil where none runs.
    private let tap: EventTap?
    // watcher holds the Accessibility observers.
    private lazy var watcher = Watcher { [unowned self] el, note in axEvent(el, note) }
    // deliver receives each event while started, nil while stopped.
    private var deliver: ((WindowEvent) -> Void)?
    // ids maps each window element whose close is observed to its id, since a destroyed element no
    // longer names its window.
    private var ids: [AXUIElement: WindowID] = [:]
    // tokens holds the notification center observers added by start.
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    // init builds a source that reads windows through store and keeps tap running while started.
    init(store: Windows, tap: EventTap? = nil) {
        self.store = store
        self.tap = tap
    }

    // waiting reports whether an app is still in its eager tries to take its observer.
    var waiting: Bool { watcher.waiting }

    // observed is how many apps are observed.
    var observed: Int { watcher.count }

    // start starts the tap, watches every regular app, and begins delivery to deliver of the window
    // events, app launches and quits, wakes and screen changes.
    func start(_ deliver: @escaping (WindowEvent) -> Void) {
        teardown()
        self.deliver = deliver
        if let tap, !tap.running {
            _ = tap.start()
        }
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
        watcher.watch(Self.regularApps())
        turned()
    }

    // stop stops the tap, ends delivery and drops every observer, so a restart registers each app
    // again instead of trusting observers made under an old grant.
    func stop() {
        teardown()
        tap?.stop()
        turned()
    }

    // teardown ends delivery and drops every observer.
    private func teardown() {
        deliver = nil
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens = []
        watcher.reset()
        ids = [:]
    }

    // watch re-arms the tap when macOS turned it off, observes every regular app and the apps of the
    // windows in scan, and the close of each of those windows, while started, so a source that
    // delivers nothing takes no observers.
    func watch(_ scan: Scan) {
        guard deliver != nil else { return }
        if let tap, !tap.running {
            _ = tap.start()
        }
        var pids = Self.regularApps()
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

    // axEvent turns one Accessibility notification into a window event. The move, resize or birth of
    // a window no scan keeps is dropped, asking the window's kind only when the last scan did not
    // keep it. A window's own move within Pace.settleSeconds of a placement marks nothing, since the
    // placement read it; any other event marks its app as woken. A window that appears has its close
    // observed at once.
    private func axEvent(_ el: AXUIElement, _ note: String) {
        guard let deliver else { return }
        if note == kAXUIElementDestroyedNotification {
            guard let id = ids.removeValue(forKey: el) ?? Windows.id(el) else { return }
            deliver(.destroyed(id))
            return
        }
        let id = Windows.id(el)
        let geometry = Pace.geometryEvents.contains(note)
        guard Pace.wakes(note, kept: store.keeps(geometry ? id : nil), eligible: Windows.eligible(el)) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let echo =
            Self.echoNotes.contains(note)
            && id.flatMap { store.echoes[$0] }.map { now - $0.at < Pace.settleSeconds } == true
        if !echo, let pid = Windows.pid(el) {
            store.appWoke[pid] = now
        }
        guard let id else {
            deliver(.wake)
            return
        }
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
    // regular app that launched or forgets one that quit. A launch of an app that shows no windows
    // only wakes. pid is nil when the note names no app.
    private func workspaceEvent(_ name: Notification.Name, pid: pid_t?, bundle: String, regular: Bool) {
        if Self.wakeNotes.contains(name) {
            deliver?(.wake)
            return
        }
        guard let pid else { return }
        if name == NSWorkspace.didLaunchApplicationNotification {
            guard regular else {
                deliver?(.wake)
                return
            }
            watcher.watch([pid])
            deliver?(.appLaunched(bundle))
        } else {
            store.forget(pid)
            watcher.forget(pid)
            deliver?(.appQuit(bundle))
        }
    }

    // regularApps returns the processes of the apps that can show windows, other than moorings.
    private static func regularApps() -> Set<pid_t> {
        let me = ProcessInfo.processInfo.processIdentifier
        return Set(
            NSWorkspace.shared.runningApplications.lazy
                .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }.map(\.processIdentifier))
    }
}
