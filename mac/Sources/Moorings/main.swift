import AppKit
import ServiceManagement
import os

import MooringsCore

// AppDelegate starts Moorings and owns its long-lived objects: the layout, the window reader, the
// poll timer, and the menu bar item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // choicesKey is the defaults key the saved choices live under.
    static let choicesKey = "choices"
    // pollSeconds is how often the layout is checked while windows are changing.
    static let pollSeconds = 0.25
    // activeSeconds is how long after the last window event the layout counts as changing.
    static let activeSeconds = 10.0
    // idleSeconds is how often the layout is checked once windows are still.
    static let idleSeconds = 2.0

    // logger writes to the unified log under the com.dcadolph.moorings subsystem.
    let logger = Logger(subsystem: "com.dcadolph.moorings", category: "anchors")
    // anchors holds the layout and decides every move.
    let anchors = Anchors(choices: Choices.decode(UserDefaults.standard.data(forKey: AppDelegate.choicesKey) ?? Data()))
    // windows reads and moves windows.
    let windows = Windows()
    // watcher wakes the poll on window events.
    private lazy var watcher = Watcher { [weak self] in self?.wake() }
    // actions applies window actions to the focused window.
    lazy var actions = ActionRunner(app: self)
    // tap watches the primary mouse button for green button clicks and drags.
    let tap = EventTap()
    // snap follows drags and snaps the dragged window to the zone under the cursor.
    lazy var snap = DragSnap(app: self)
    // hotkeys runs a window action when its shortcut is pressed.
    lazy var hotkeys = Hotkeys { [weak self] name in self?.actions.run(name) }
    // item is the menu bar status item.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // timer runs tick every pollSeconds.
    private var timer: Timer?
    // woke is when the last window event came.
    private var woke = 0.0
    // polled is when the last pass ran.
    private var polled = 0.0
    // started reports whether the first pass ran, which opens the anchored apps.
    private var started = false

    // now returns the time in seconds since boot.
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    // applicationDidFinishLaunching builds the menu, subscribes to events, and starts the poll.
    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "sailboat", accessibilityDescription: "Moorings")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didUnhideApplicationNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification,
                           object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if !windows.trusted {
            logger.notice("Accessibility is not granted: windows will not move")
        }
        anchors.launch(now: Self.now)
        tap.onDown = { [weak self] p, option in
            guard let self else { return false }
            if self.zoomDown(p, option: option) {
                return true
            }
            self.snap.pressed()
            return false
        }
        tap.onDrag = { [weak self] p, option in self?.snap.dragged(p, option: option) }
        tap.onUp = { [weak self] _, _ in self?.snap.released() }
        tap.start()
        rebind()
        refreshShortcuts()
        wake()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        moor()
    }

    // applicationShouldHandleReopen opens the menu when Moorings is opened again while it runs, so a
    // second open from Applications shows it is already there.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        item.button?.performClick(nil)
        return false
    }

    // application handles moorings:// links: status logs the layout and moor runs a pass.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "moorings" {
            switch url.host() {
            case "status": status()
            case "moor": moor()
            case "action": runLink(url)
            default: logger.notice("unknown link: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    // menuNeedsUpdate rebuilds the menu from the current state each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in MenuBuilder(app: self).items() {
            menu.addItem(entry)
        }
    }

    // wake marks windows as changing, so the poll runs every pollSeconds again.
    func wake() {
        woke = Self.now
    }

    // tick runs a pass every pollSeconds while windows are changing and every idleSeconds once they
    // have been still for activeSeconds.
    private func tick() {
        let t = Self.now
        if t - woke > Self.activeSeconds && t - polled < Self.idleSeconds {
            return
        }
        moor()
    }

    // moor runs one pass and applies its moves. The first pass after launch opens the anchored apps
    // that have no window, in the background.
    func moor() {
        polled = Self.now
        guard windows.trusted else { return }
        if !tap.running {
            tap.start()
        }
        let screens = Screens.current()
        let (list, focused) = windows.scan(screens)
        watcher.watch(windows.scanned)
        if anchors.hasCastOff {
            anchors.prune(alive: Windows.alive())
        }
        let scene = Scene(screen: screens.wide, windows: list, focused: focused?.id,
                          mouseHeld: NSEvent.pressedMouseButtons & 1 != 0, now: Self.now)
        for move in anchors.moor(scene) {
            apply(move)
        }
        for id in anchors.justReleased {
            logger.notice("TODO banner: window \(id) was moved by hand: released")
        }
        if !started {
            started = true
            for bundle in anchors.opening() {
                open(bundle, background: true)
            }
        }
    }

    // apply carries out one move: it takes a window out of native fullscreen, or moves it, reads
    // where it landed, and moves it once more when it kept a larger size than it was given.
    private func apply(_ move: Move) {
        if move.exitFullScreen {
            windows.exitFullScreen(move.id)
            return
        }
        windows.move(move.id, to: move.frame)
        guard let got = windows.frame(move.id), let again = anchors.landed(move, got: got) else { return }
        logger.notice("window \(move.id) keeps a size of at least \(Int(got.w))x\(Int(got.h)): leaving it that size")
        windows.move(again.id, to: again.frame)
    }

    // zoomDown reports whether a press at p is on a green button moorings handles, and if so runs
    // the lift, fill or re-moor after the event, so the tap never waits on it.
    private func zoomDown(_ p: CGPoint, option: Bool) -> Bool {
        guard windows.trusted,
              let action = anchors.zoomClick(Point(x: p.x, y: p.y), option: option, front: Windows.front())
        else { return false }
        DispatchQueue.main.async { [weak self] in self?.zoom(action) }
        return true
    }

    // zoom carries out a green button action.
    private func zoom(_ action: ZoomAction) {
        switch action {
        case let .lift(id), let .lower(id):
            anchors.toggleLift(id: id)
            if anchors.isLifted(id) {
                windows.raise(id)
            }
        case let .remoor(id):
            anchors.remoor(id)
        case let .fill(id), let .restore(id):
            let screens = Screens.current()
            guard let w = windows.scan(screens).windows.first(where: { $0.id == id }) else { return }
            if case .fill = action {
                if actions.apply("maximize", to: w, screens: screens) {
                    anchors.markFilled(id, windows.frame(id))
                }
            } else {
                anchors.markFilled(id, nil)
                actions.apply("restore", to: w, screens: screens)
            }
        }
        wake()
        moor()
    }

    // save writes the choices to defaults, binds the shortcuts again, then runs a pass so the change
    // shows at once.
    func save() {
        if let data = try? Choices.encode(anchors.choices) {
            UserDefaults.standard.set(data, forKey: Self.choicesKey)
        }
        rebind()
        refreshShortcuts()
        wake()
        moor()
    }

    // rebind registers every shortcut in effect and logs the problems with the saved ones.
    func rebind() {
        let bindings = Bindings(anchors.choices)
        for p in bindings.problems {
            logger.notice("\(p, privacy: .public)")
        }
        hotkeys.bind(bindings.map)
    }

    // refreshShortcuts turns the shortcuts off while an app in the ignore list is in front.
    func refreshShortcuts() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        hotkeys.setEnabled(front.map { !anchors.choices.ignores.contains($0) } ?? true)
    }

    // runLink runs the action a moorings://action?name= link asks for.
    private func runLink(_ url: URL) {
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
        guard let name, actions.runnable(name) else {
            logger.notice("a moorings link asked for unknown action \(name ?? "none", privacy: .public)")
            return
        }
        actions.run(name)
    }

    // open opens the app with bundle the way a Dock click does, which launches it or asks a running
    // app with no window for a new one. A background open leaves the front app in front.
    func open(_ bundle: String, background: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = (background ? ["-g"] : []) + ["-b", bundle]
        do {
            try task.run()
        } catch {
            logger.error("open \(bundle, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // launchAtLogin reports whether Moorings is registered as a login item.
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    // setLaunchAtLogin registers or unregisters Moorings as a login item.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    // status logs the trust state, the screens, the slots, and every window the scan sees.
    private func status() {
        let screens = Screens.current()
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        logger.notice("status: trusted=\(self.windows.trusted) build=\(build, privacy: .public) ultrawide=\(String(describing: screens.wide), privacy: .public) paused=\(self.anchors.choices.paused)")
        for (key, bundle) in anchors.assignments().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            logger.notice("slot \(key.rawValue, privacy: .public): \(bundle, privacy: .public)")
        }
        for w in windows.scan(screens).windows {
            logger.notice("window \(w.id) \(w.bundle, privacy: .public) frame=\(w.frame.description, privacy: .public) wide=\(w.onUltrawide) main=\(w.isMain) panel=\(w.isFilePanel) pinned=\(self.anchors.pinned(w)) castOff=\(self.anchors.isCastOff(w.id))")
        }
    }

    // workspaceChanged wakes the poll when an app or screen changes, and turns the shortcuts off or
    // on when the front app changes.
    @objc private func workspaceChanged(_ note: Notification) {
        if note.name == NSWorkspace.didActivateApplicationNotification {
            refreshShortcuts()
        }
        if note.name == NSApplication.didChangeScreenParametersNotification {
            anchors.screensChanged()
        }
        wake()
    }

    // appQuit forgets a quit app's elements and observer and wakes the poll.
    @objc private func appQuit(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            windows.forget(app.processIdentifier)
            watcher.forget(app.processIdentifier)
        }
        wake()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
