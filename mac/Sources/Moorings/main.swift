import AppKit
import ServiceManagement
import os

import MooringsCore

// AppDelegate starts Moorings and owns its long-lived objects: the layout, the window reader, the
// pass timer, and the menu bar item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // choicesKey is the defaults key the saved choices live under.
    static let choicesKey = "choices"
    // launchSeconds is how long after an app launches passes keep looking for its first window,
    // in case it shows one before it takes an observer.
    static let launchSeconds = 30.0

    // logger writes to the unified log under the com.dcadolph.moorings subsystem.
    let logger = Logger(subsystem: "com.dcadolph.moorings", category: "anchors")
    // anchors holds the layout and decides every move.
    let anchors = Anchors(choices: Choices.decode(UserDefaults.standard.data(forKey: AppDelegate.choicesKey) ?? Data()))
    // windows reads and moves windows.
    let windows = Windows()
    // watcher wakes the passes on window events.
    private lazy var watcher = Watcher { [weak self] in self?.wake() }
    // actions applies window actions to the focused window.
    lazy var actions = ActionRunner(app: self)
    // accessibilityPane is the Privacy and Security pane that grants Accessibility.
    static let accessibilityPane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    // releasesPage is the project's releases page.
    static let releasesPage = URL(string: "https://github.com/dcadolph/moorings/releases")!
    // checkedKey and versionKey are the defaults keys for the last update check and the version
    // that last ran.
    static let checkedKey = "updateChecked"
    static let versionKey = "lastVersion"
    // supportURL is the https tip link baked into the bundle, nil when the build has none.
    static let supportURL: URL? = {
        guard let text = (Bundle.main.object(forInfoDictionaryKey: "MooringsSupportURL") as? String)?
            .trimmingCharacters(in: .whitespaces), let url = URL(string: text), url.scheme == "https", url.host != nil
        else { return nil }
        return url
    }()

    // installer puts a downloaded copy into Applications and tidies the disk image after.
    let installer = Installer()
    // banner shows what moorings did.
    let banner = BannerPanel()
    // stackBadge counts the stacked windows under the pointer when the choice is on.
    let stackBadge = StackBadge()
    // update is a newer release found by the daily check, nil when none.
    var update: ReleaseInfo?
    // launched is when moorings started.
    private let launched = Date()
    // wasTrusted is the Accessibility state at the last tick, to catch the grant.
    private var wasTrusted = true
    // updateTimer runs the daily update check.
    private var updateTimer: Timer?
    // tap watches the primary mouse button for green button clicks and drags.
    let tap = EventTap()
    // selftest drives TextEdit windows through the layout from the moorings://selftest link.
    lazy var selftest = Selftest(app: self)
    // settings is the settings window.
    lazy var settings = SettingsWindow(app: self)
    // organizer lays out several windows at once and keeps the workspaces.
    lazy var organizer = Organizer(app: self)
    // snap follows drags and snaps the dragged window to the zone under the cursor.
    lazy var snap = DragSnap(app: self)
    // hotkeys runs a window action when its shortcut is pressed.
    lazy var hotkeys = Hotkeys { [weak self] name in self?.actions.run(name) }
    // overlay throws a window while the overlay's trigger key is held.
    lazy var overlay = TriggerOverlay(app: self)
    // stasher parks windows at a screen edge.
    lazy var stasher = Stasher(app: self)
    // gridPicker pops a grid of cells for the grid actions.
    lazy var gridPicker = GridPicker(app: self)
    // strips edits the strip widths and row heights on screen.
    lazy var strips = StripEditor(app: self)
    // tiler keeps free windows in the tiling mode's layout.
    lazy var tiler = Tiler(app: self)
    // edges moves the edge two windows share for both while the edge resize keys are held.
    lazy var edges = EdgeResizer(app: self)
    // hover moves or resizes the window under the pointer while the hover modifiers are held.
    lazy var hover = HoverMover(app: self)
    // item is the menu bar status item.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // timer runs the next pass, nil when none is due until an event.
    private var timer: Timer?
    // due is when timer fires, nil when no timer is set.
    private var due: Double?
    // woke is when the last window event came.
    private var woke = 0.0
    // launching is when passes stop looking for the first window of an app that just launched.
    private var launching = 0.0
    // badgeTimer reads the pointer for the stack badge while the badge is on.
    private var badgeTimer: Timer?
    // started reports whether the first pass ran, which opens the anchored apps.
    private var started = false
    // quitting reports whether Quit Moorings was chosen, so the icon stays blank while the boat sinks.
    private var quitting = false
    // sinking plays the quit animation.
    private let sinking = Sinking()

    // now returns the time in seconds since boot.
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    // applicationDidFinishLaunching builds the menu, subscribes to events, and runs the first pass.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if installer.offerMove() {
            return
        }
        installer.offerTrash()
        item.button?.image = Mark.image()
        showIcon()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification,
                           object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        wasTrusted = windows.trusted
        showTrust()
        if !wasTrusted {
            logger.notice("Accessibility is not granted: windows will not move")
            notify("Moorings needs Accessibility", "Click here to open Privacy & Security, then turn on Moorings so it "
                + "can move windows.") { NSWorkspace.shared.open(Self.accessibilityPane) }
        } else {
            releaseMessage()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.checkUpdate() }
        }
        updateTimer?.tolerance = 10
        anchors.launch(now: Self.now)
        _ = organizer
        tap.onDown = { [weak self] p, flags in
            guard let self else { return false }
            if self.gridPicker.showing {
                if self.gridPicker.contains(p) {
                    return false
                }
                self.gridPicker.cancel()
            }
            self.stasher.clicked(p)
            if self.edges.pressed(p, flags: flags) {
                return true
            }
            if self.buttonDown(p, flags: flags) || self.zoomDown(p, option: flags.contains(.maskAlternate)) {
                return true
            }
            self.snap.pressed(p)
            return false
        }
        tap.onDoubleClick = { [weak self] p in self?.actions.titleBarClick(p) }
        tap.onDrag = { [weak self] p, flags in
            guard let self else { return }
            if self.edges.active {
                self.edges.dragged(p)
            } else {
                self.snap.dragged(p, flags: flags)
            }
        }
        tap.onSwallowedUp = { [weak self] _ in self?.edges.released() }
        tap.onUp = { [weak self] _, _ in
            self?.snap.released()
            self?.tiler.mouseUp()
            self?.wake()
        }
        tap.onOther = { [weak self] button, down in self?.mouseButton(button, down: down) ?? false }
        tap.onFlags = { [weak self] flags, p in
            self?.overlay.flagsChanged(flags, at: p)
            self?.hover.flagsChanged(flags, at: p)
        }
        hotkeys.onGrab = { [weak self] tag in
            guard let self else { return }
            if self.gridPicker.showing {
                self.gridPicker.key(tag)
            } else {
                self.overlay.key(tag)
            }
        }
        tap.start()
        rebind()
        refreshShortcuts()
        wake()
        moor()
    }

    // quit pulls the menu bar sailboat under the water, then quits. With Reduce Motion on, the icon
    // hidden or no button on screen, it quits at once.
    func quit() {
        guard !quitting else { return }
        quitting = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, item.isVisible, let button = item.button,
              let win = button.window else {
            NSApp.terminate(nil)
            return
        }
        let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
        button.image = NSImage(size: button.image?.size ?? NSSize(width: 18, height: 18))
        sinking.play(over: rect, appearance: button.effectiveAppearance,
                     accent: BannerPanel.color(Palette.harbor.accent)) {
            NSApp.terminate(nil)
        }
    }

    // applicationWillTerminate puts stashed windows back, so none is left parked off screen.
    func applicationWillTerminate(_ notification: Notification) {
        stasher.unstashAll()
    }

    // applicationShouldHandleReopen opens the settings window when Moorings is opened again while it
    // runs, so a second open from Applications shows it is already there.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    // application handles moorings:// links: status logs the layout and moor runs a pass.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "moorings" {
            switch url.host() {
            case "status": status()
            case "moor": moor()
            case "action": runLink(url)
            case "settings": settings.show()
            case "selftest":
                let apps = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "apps" }?.value
                selftest.start(apps: apps?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
            case "banner":
                let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
                notify("Moorings", text ?? "")
            case "workspace":
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
                organizer.recall(name ?? "")
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

    // popMenu opens the menu under the pointer as a context menu. Moorings is not brought forward,
    // so the front app's entries and window actions still act on the window that was in front.
    func popMenu() {
        let menu = NSMenu()
        for entry in MenuBuilder(app: self).items() {
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle.
    func wake() {
        let t = Self.now
        woke = t
        if let due, due <= t + Pace.pollSeconds {
            return
        }
        schedule(t + Pace.pollSeconds)
    }

    // schedule sets the timer for the next pass at time at, or clears it when at is nil.
    private func schedule(_ at: Double?) {
        timer?.invalidate()
        timer = nil
        due = at
        guard let at else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(0.001, at - Self.now), repeats: false) { _ in
            MainActor.assumeIsolated {
                self.timer = nil
                self.due = nil
                self.tick()
            }
        }
    }

    // pace sets the timer for the pass after the one that just ran: soon while windows change,
    // every Pace.busySeconds while something pending sends no event, at the next deadline, or not
    // at all. It also starts or stops the stack badge's pointer reads.
    private func pace() {
        let t = Self.now
        let busy = !windows.trusted || watcher.waiting || organizer.waiting || t < launching
        schedule(Pace.next(now: t, woke: woke, busy: busy, deadlines: anchors.deadlines() + organizer.deadlines()))
        if anchors.choices.stacking.badge, badgeTimer == nil {
            badgeTimer = Timer.scheduledTimer(withTimeInterval: Pace.pollSeconds, repeats: true) { _ in
                MainActor.assumeIsolated { self.updateBadge() }
            }
        } else if !anchors.choices.stacking.badge, let badgeTimer {
            badgeTimer.invalidate()
            self.badgeTimer = nil
            stackBadge.hide()
        }
    }

    // updateBadge shows or hides the stack badge for the pointer's place.
    private func updateBadge() {
        stackBadge.update(palette: .harbor, choices: anchors.choices.stacking,
                          gap: anchors.choices.gapPx)
    }

    // tick catches an Accessibility grant, then runs the pass that was due.
    private func tick() {
        if windows.trusted != wasTrusted {
            wasTrusted = windows.trusted
            showTrust()
            if wasTrusted {
                tap.start()
                notify("Moorings is ready", "Accessibility is on. Anchored apps take their slots now.")
            }
        }
        moor()
    }

    // moor runs one pass and applies its moves. The first pass after launch opens the anchored apps
    // that have no window, in the background.
    func moor() {
        defer { pace() }
        logger.debug("pass")
        guard windows.trusted else { return }
        if !tap.running {
            tap.start()
        }
        let screens = Screens.current()
        let (list, focused) = windows.scan(screens)
        watcher.watch(Self.regularApps())
        watcher.watchClosing(windows.elements)
        if anchors.hasCastOff || !anchors.stashed.isEmpty {
            anchors.prune(alive: Windows.alive())
        }
        let scene = Scene(screen: screens.wide, windows: list, focused: focused?.id,
                          mouseHeld: NSEvent.pressedMouseButtons & 1 != 0 || hover.active, now: Self.now)
        for move in anchors.moor(scene) {
            apply(move)
        }
        organizer.seen(list, screens: screens)
        tiler.pass(list, screens: screens, mouseHeld: scene.mouseHeld)
        for id in anchors.justReleased {
            logger.notice("window \(id) was moved by hand: released")
            let name = list.first { $0.id == id }.map { appName($0.bundle) } ?? "The window"
            let how = Bindings(anchors.choices).map["restore"].map { ",\nor press \($0.spelled)" } ?? ""
            notify("\(name) released", "Click its green button to put it back\(how).")
        }
        hintAnchor(screens)
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
        guard let got = windows.frame(move.id) else {
            anchors.unread(move)
            return
        }
        guard let again = anchors.landed(move, got: got) else { return }
        logger.notice("window \(move.id) read back at \(Int(got.w))x\(Int(got.h)) after a move: holding that size for now")
        windows.move(again.id, to: again.frame)
    }

    // mouseButton runs the action bound to an extra mouse button when it goes down, and reports
    // whether the button is bound, so both halves are swallowed. Unbound buttons, and every button
    // while paused or while an ignored app is in front, pass on.
    private func mouseButton(_ button: Int, down: Bool) -> Bool {
        let sizes = Set(Bindings(anchors.choices).sizes.map(\.name))
        guard !anchors.choices.paused, hotkeys.enabled,
              let name = MouseButtons.valid(anchors.choices.mouseButtons, sizes: sizes).map[button]
        else { return false }
        if down {
            DispatchQueue.main.async { [weak self] in self?.actions.run(name) }
        }
        return true
    }

    // buttonDown reports whether a press at p is on a title bar button bound to an action for the
    // modifiers held, and if so runs the action on that button's window after the event. The element
    // is read only for a press in a window's top left corner while a binding takes these modifiers, and
    // the green button of an anchored window keeps its lift.
    private func buttonDown(_ p: CGPoint, flags: CGEventFlags) -> Bool {
        let choices = anchors.choices
        guard !choices.buttonClicks.isEmpty, !choices.paused, hotkeys.enabled, windows.trusted,
              let modifier = ButtonClicks.modifier(shift: flags.contains(.maskShift),
                                                   option: flags.contains(.maskAlternate),
                                                   command: flags.contains(.maskCommand),
                                                   control: flags.contains(.maskControl)),
              ButtonClicks.bound(choices.buttonClicks, modifier: modifier)
        else { return false }
        let point = Point(x: p.x, y: p.y)
        let front = Windows.front()
        let under = { (f: Frame) in p.x >= f.x && p.x < f.x + f.w && p.y >= f.y && p.y < f.y + f.h }
        guard let top = front.first(where: { under($0.frame) }), ButtonClicks.near(point, top.frame),
              let hit = Windows.button(p), hit.id == top.id, let button = WindowButton(subrole: hit.subrole),
              let name = ButtonClicks.action(choices.buttonClicks, button, modifier,
                                             sizes: Set(Bindings(choices).sizes.map(\.name)))
        else { return false }
        if button == .green {
            switch anchors.zoomClick(point, option: flags.contains(.maskAlternate), front: front) {
            case .lift, .lower, .remoor: return false
            default: break
            }
        }
        DispatchQueue.main.async { [weak self] in self?.actions.run(name, window: hit.id) }
        return true
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
                if actions.apply("maximize", to: w, screens: screens), let f = windows.frame(id) {
                    anchors.markFilled(id, f, from: w.frame)
                }
            } else if let f = anchors.unfill(id) {
                windows.move(id, to: f)
            }
        }
        wake()
        moor()
    }

    // hintKey is the defaults key that records the first anchor hint was shown.
    static let hintKey = "anchorHint"

    // appName returns the display name of the running app with bundle, the bundle when not found.
    func appName(_ bundle: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName ?? bundle
    }

    // hintAnchor says once how to anchor an app, while an ultrawide is attached and nothing is
    // anchored. Emptied slots count as a choice.
    private func hintAnchor(_ screens: Screens) {
        let defaults = UserDefaults.standard
        guard screens.wide != nil, anchors.choices.slots.isEmpty, !defaults.bool(forKey: Self.hintKey) else { return }
        defaults.set(true, forKey: Self.hintKey)
        notify("Anchor an app to an edge", "Click the app, then choose Anchor and its name near the top of the "
            + "Moorings menu and pick a slot.")
    }

    // notify shows a banner in the harbor palette. A click on it runs action.
    func notify(_ title: String, _ body: String, action: (@MainActor () -> Void)? = nil) {
        logger.notice("banner: \(body, privacy: .public)")
        banner.show(title, body, palette: .harbor, action: action)
    }

    // showTrust shows a warning mark on the menu bar icon while Accessibility is missing.
    private func showTrust() {
        guard !quitting else { return }
        item.button?.image = windows.trusted ? Mark.image()
            : NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Moorings")
    }

    // releaseMessage says once that moorings was updated, on the first launch of a new version.
    private func releaseMessage() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let last = UserDefaults.standard.string(forKey: Self.versionKey)
        UserDefaults.standard.set(version, forKey: Self.versionKey)
        guard let last, last != version, !version.isEmpty else { return }
        notify("Moorings \(version)", "Updated from \(last). Click to see what is new.") {
            NSWorkspace.shared.open(Self.releasesPage.appendingPathComponent("tag/v\(version)"))
        }
    }

    // checkUpdate looks for a newer release once a day, a minute after launch at the earliest.
    private func checkUpdate() {
        guard anchors.choices.checkUpdates, update == nil else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.checkedKey) as? Date
        guard UpdateSchedule.isDue(lastChecked: last, launched: launched, now: Date()),
              let current = ReleaseVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
        else { return }
        defaults.set(Date(), forKey: Self.checkedKey)
        let checker = UpdateChecker(client: URLSessionClient(), current: current)
        Task { @MainActor in
            do {
                self.update = try await checker.check()
            } catch {
                self.logger.notice("update check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // save writes the choices to defaults, binds the shortcuts again, then runs a pass so the change
    // shows at once.
    func save() {
        if let data = try? Choices.encode(anchors.choices) {
            UserDefaults.standard.set(data, forKey: Self.choicesKey)
        }
        rebind()
        refreshShortcuts()
        showIcon()
        wake()
        moor()
    }

    // showIcon shows the menu bar icon unless the choices hide it. Opening Moorings again while it
    // runs opens the settings, where the icon can be turned back on.
    private func showIcon() {
        item.isVisible = !anchors.choices.behavior.hideMenuBarIcon
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
    func open(_ bundle: String, background: Bool, target: String? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = (background ? ["-g"] : []) + ["-b", bundle] + (target.map { [$0] } ?? [])
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
        for line in windows.explain(screens) {
            logger.notice("scan \(line, privacy: .public)")
        }
    }

    // workspaceChanged wakes the passes when an app or screen changes, watches an app that just
    // launched, and turns the shortcuts off or on when the front app changes.
    @objc private func workspaceChanged(_ note: Notification) {
        if note.name == NSWorkspace.didLaunchApplicationNotification,
           let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.activationPolicy == .regular {
            launching = Self.now + Self.launchSeconds
            watcher.watch([app.processIdentifier])
        }
        if note.name == NSWorkspace.didActivateApplicationNotification {
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                windows.lastFront = app.processIdentifier
                if windows.trusted, Behavior.disablesEnhancedUIOnActivation(
                    anchors.choices.behavior.enhancedUI, bundle: app.bundleIdentifier,
                    assistive: NSWorkspace.shared.isVoiceOverEnabled) {
                    Windows.dropEnhancedUI(app.processIdentifier)
                }
            }
            refreshShortcuts()
        }
        if note.name == NSApplication.didChangeScreenParametersNotification {
            anchors.screensChanged()
            organizer.screensChanged()
        }
        wake()
    }

    // regularApps returns the processes of the apps that can show windows, other than moorings.
    private static func regularApps() -> Set<pid_t> {
        let me = ProcessInfo.processInfo.processIdentifier
        return Set(NSWorkspace.shared.runningApplications.lazy
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }.map(\.processIdentifier))
    }

    // appQuit forgets a quit app's elements and observer and wakes the passes.
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
