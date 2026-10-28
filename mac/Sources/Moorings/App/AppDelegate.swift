import AppKit
import ServiceManagement
import os

import MooringsCore
import MooringsEngine

// AppDelegate starts Moorings and owns its long-lived objects: the Mac adapters, the engine built
// on them, and the menu bar item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // choicesKey is the defaults key the saved choices live under.
    static let choicesKey = "choices"

    // logger writes to the unified log under the com.dcadolph.moorings subsystem.
    let logger = Logger(subsystem: "com.dcadolph.moorings", category: "anchors")
    // windows reads and moves windows.
    let windows = Windows()
    // pointer reads and warps the mouse pointer.
    let pointer = MacPointer()
    // apps names and opens apps.
    let apps = MacApps()
    // log writes the engine's lines to the unified log.
    let log = MacLog()
    // timers hands each engine object its own scheduler.
    let timers = MacTimers()
    // keys reads whether the shortcuts are on and grabs the keys a hold takes.
    lazy var keys = MacKeys(hotkeys)
    // events wakes the passes on window, app and screen events and keeps the tap running.
    lazy var events = MacEvents(store: windows, tap: tap)
    // accessibilityPane is the Privacy and Security pane that grants Accessibility.
    static let accessibilityPane = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    // releasesPage is the project's releases page.
    static let releasesPage = URL(string: "https://github.com/dcadolph/moorings/releases")!
    // checkedKey and versionKey are the defaults keys for the last update check and the version
    // that last ran.
    static let checkedKey = "updateChecked"
    static let versionKey = "lastVersion"
    // supportURL is the https tip link baked into the bundle, nil when the build has none.
    static let supportURL: URL? = {
        guard
            let text = (Bundle.main.object(forInfoDictionaryKey: "MooringsSupportURL") as? String)?
                .trimmingCharacters(in: .whitespaces), let url = URL(string: text), url.scheme == "https",
            url.host != nil
        else { return nil }
        return url
    }()

    // installer puts a downloaded copy into Applications and tidies the disk image after.
    let installer = Installer()
    // banner shows what moorings did.
    let banner = BannerPanel()
    // badge is the stack badge's panel.
    let badge = BadgePanel()
    // update is a newer release found by the update check, nil when none.
    var update: ReleaseInfo?
    // launched is when moorings started.
    private let launched = Date()
    // updateTimer runs the update check.
    private var updateTimer: Timer?
    // tap watches the primary mouse button for green button clicks and drags.
    let tap = EventTap()
    // selftest drives TextEdit windows through the layout from the moorings://selftest link.
    lazy var selftest = Selftest(app: self)
    // settings is the settings window.
    lazy var settings = SettingsWindow(app: self)
    // snap follows drags and snaps the dragged window to the zone under the cursor.
    lazy var snap = MacDrag(app: self)
    // platform is what the engine reads and drives on the Mac. A save shows the choices the menu bar
    // icon, the ignore list and the anchor hint read.
    lazy var platform = macPlatform()
    // engine builds and runs every engine object on the Mac's platform, with every routed action and
    // the menu and strip editor.
    lazy var engine: Engine = {
        let e = Engine(
            platform: platform, features: .all, platformActions: MacActions(app: self),
            throwViews: ThrowViews(footprint: Footprint(), grid: GridPanel()))
        e.passes.greenButton = true
        return e
    }()
    // hotkeys runs a window action when its shortcut is pressed.
    lazy var hotkeys = Hotkeys { [weak self] name in self?.engine.actions.run(name) }
    // strips edits the strip widths and row heights on screen.
    lazy var strips = StripEditor(app: self)
    // edges moves the edge two windows share for both while the edge resize keys are held.
    lazy var edges = EdgeResizer(app: self)
    // item is the menu bar status item.
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // quitting reports whether Quit Moorings was chosen, so the icon stays blank while the boat sinks.
    private var quitting = false
    // sinking plays the quit animation.
    private let sinking = Sinking()

    // now returns the time in seconds since boot.
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    // applicationDidFinishLaunching builds the menu, subscribes to events, and runs the first pass.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Windows.timeout)
        if installer.offerMove() {
            return
        }
        installer.offerTrash()
        item.button?.image = Mark.image()
        showIcon()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontChanged(_:)), name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        events.turned = { [weak self] in self?.showTrust() }
        showTrust()
        if !windows.trusted {
            logger.notice("Accessibility is not granted: windows will not move")
            notify(
                "Moorings needs Accessibility",
                "Click here to open Privacy & Security, then turn on Moorings so it "
                    + "can move windows."
            ) { NSWorkspace.shared.open(Self.accessibilityPane) }
        } else {
            releaseMessage()
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.checkUpdate() }
        }
        updateTimer?.tolerance = 10
        tap.onDown = { [weak self] p, flags in
            guard let self else { return false }
            let picker = self.engine.gridPicker
            if picker.showing {
                if picker.contains(Point(x: p.x, y: p.y)) {
                    return false
                }
                picker.cancel()
            }
            self.engine.stasher.clicked(Point(x: p.x, y: p.y))
            if self.edges.pressed(p, flags: flags) {
                return true
            }
            if self.buttonDown(p, flags: flags) || self.zoomDown(p, option: flags.contains(.maskAlternate)) {
                return true
            }
            self.snap.pressed(p)
            return false
        }
        tap.onDoubleClick = { [weak self] p in self?.titleBarClick(p) }
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
            self?.engine.tiler.mouseUp()
            self?.engine.wake()
        }
        tap.onOther = { [weak self] button, down in self?.mouseButton(button, down: down) ?? false }
        tap.onFlags = { [weak self] flags, p in
            let m = Modifiers(flags: flags)
            self?.engine.overlay.flagsChanged(m, at: Point(x: p.x, y: p.y))
            self?.engine.hover.flagsChanged(m, at: Point(x: p.x, y: p.y))
        }
        engine.start()
        refreshShortcuts()
        hintAnchor(Screens.current())
    }

    // quit pulls the menu bar sailboat under the water, then quits. With Reduce Motion on, the icon
    // hidden or no button on screen, it quits at once.
    func quit() {
        guard !quitting else { return }
        quitting = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, item.isVisible, let button = item.button,
            let win = button.window
        else {
            NSApp.terminate(nil)
            return
        }
        let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
        button.image = NSImage(size: button.image?.size ?? NSSize(width: 18, height: 18))
        sinking.play(
            over: rect, appearance: button.effectiveAppearance,
            accent: BannerPanel.color(Palette.harbor.accent)
        ) {
            NSApp.terminate(nil)
        }
    }

    // applicationWillTerminate shuts the engine down, which puts stashed windows back, so none is left
    // parked off screen.
    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
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
            case "moor": engine.moor()
            case "action": runLink(url)
            case "settings": settings.show()
            case "selftest":
                let apps = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                    $0.name == "apps"
                }?.value
                selftest.start(apps: apps?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
            case "banner":
                let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                    $0.name == "text"
                }?.value
                notify("Moorings", text ?? "")
            case "workspace":
                let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
                    $0.name == "name"
                }?.value
                engine.workspaces.recall(name ?? "")
            default: logger.notice("unknown link: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    // menuNeedsUpdate rebuilds the menu from the current state each time it opens, and checks for a
    // release when the last check is over an hour old so the next open can offer it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        checkUpdate(fresh: UpdateSchedule.menuSeconds)
        menu.removeAllItems()
        for entry in MenuBuilder(app: self).items() {
            menu.addItem(entry)
        }
    }

    // titleBarClick maximizes or restores the window whose title bar was double-clicked at p. It needs
    // the choice on and macOS set to do nothing on a title bar double-click, as Rectangle does, so
    // the two never both act. The window is read after the event, never inside the tap.
    func titleBarClick(_ p: CGPoint) {
        let b = engine.anchors.choices.behavior
        guard b.doubleClickTitleBar, !engine.anchors.choices.paused, windows.trusted else { return }
        guard UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") == "None" else {
            log.note(
                .actions,
                "title bar double-click: macOS handles it; set Double-click a window's title bar to Do Nothing")
            return
        }
        DispatchQueue.main.async { [self] in
            guard let hit = Windows.hit(p),
                Behavior.onTitleBar(Point(x: p.x, y: p.y), window: hit.frame, button: hit.button, role: hit.role)
            else { return }
            let screens = Screens.current()
            guard let w = windows.scan(screens).windows.first(where: { $0.id == hit.id }),
                !b.doubleClickIgnoredApps.contains(w.bundle)
            else { return }
            engine.actions.titleBar(w, screens: screens)
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

    // mouseButton runs the action bound to an extra mouse button when it goes down, and reports
    // whether the button is bound, so both halves are swallowed. Unbound buttons, and every button
    // while paused or while an ignored app is in front, pass on.
    private func mouseButton(_ button: Int, down: Bool) -> Bool {
        let sizes = Set(Bindings(engine.anchors.choices).sizes.map(\.name))
        guard !engine.anchors.choices.paused, hotkeys.enabled,
            let name = MouseButtons.valid(engine.anchors.choices.mouseButtons, sizes: sizes).map[button]
        else { return false }
        if down {
            DispatchQueue.main.async { [weak self] in self?.engine.actions.run(name) }
        }
        return true
    }

    // buttonDown reports whether a press at p is on a title bar button bound to an action for the
    // modifiers held, and if so runs the action on that button's window after the event. The element
    // is read only for a press in a window's top left corner while a binding takes these modifiers, and
    // the green button of an anchored window keeps its lift.
    private func buttonDown(_ p: CGPoint, flags: CGEventFlags) -> Bool {
        let choices = engine.anchors.choices
        guard !choices.buttonClicks.isEmpty, !choices.paused, hotkeys.enabled, windows.trusted,
            let modifier = ButtonClicks.modifier(
                shift: flags.contains(.maskShift),
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
            let name = ButtonClicks.action(
                choices.buttonClicks, button, modifier,
                sizes: Set(Bindings(choices).sizes.map(\.name)))
        else { return false }
        if button == .green {
            switch engine.anchors.zoomClick(point, option: flags.contains(.maskAlternate), front: front) {
            case .lift, .lower, .remoor: return false
            default: break
            }
        }
        DispatchQueue.main.async { [weak self] in self?.engine.actions.run(name, window: hit.id) }
        return true
    }

    // zoomDown reports whether a press at p is on a green button moorings handles, and if so runs
    // the lift, fill or re-moor after the event, so the tap never waits on it.
    private func zoomDown(_ p: CGPoint, option: Bool) -> Bool {
        guard windows.trusted,
            let action = engine.anchors.zoomClick(Point(x: p.x, y: p.y), option: option, front: Windows.front())
        else { return false }
        DispatchQueue.main.async { [weak self] in self?.zoom(action) }
        return true
    }

    // zoom carries out a green button action.
    private func zoom(_ action: ZoomAction) {
        switch action {
        case let .lift(id), let .lower(id):
            engine.anchors.toggleLift(id: id)
            if engine.anchors.isLifted(id) {
                windows.raise(id)
            }
        case let .remoor(id):
            engine.anchors.remoor(id)
        case let .fill(id), let .restore(id):
            let screens = Screens.current()
            guard let w = windows.scan(screens).windows.first(where: { $0.id == id }) else { return }
            if case .fill = action {
                if engine.actions.apply("maximize", to: w, screens: screens), let f = windows.frame(id) {
                    engine.anchors.markFilled(id, f, from: w.frame)
                }
            } else if let f = engine.anchors.unfill(id) {
                windows.move(id, to: f)
            }
        }
        engine.wake()
        engine.moor()
    }

    // hintKey is the defaults key that records the first anchor hint was shown.
    static let hintKey = "anchorHint"

    // appName returns the name to show for the app with bundle.
    func appName(_ bundle: String) -> String {
        apps.name(bundle)
    }

    // hintAnchor says once how to anchor an app, while an ultrawide is attached and nothing is
    // anchored. Emptied slots count as a choice. It runs at launch, when the displays change and after
    // each save.
    func hintAnchor(_ screens: Screens) {
        let defaults = UserDefaults.standard
        guard screens.wide != nil, engine.anchors.choices.slots.isEmpty, !defaults.bool(forKey: Self.hintKey) else {
            return
        }
        defaults.set(true, forKey: Self.hintKey)
        notify(
            "Anchor an app to an edge",
            "Click the app, then choose Anchor and its name near the top of the "
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
        item.button?.image =
            windows.trusted
            ? Mark.image()
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

    // checkUpdate looks for a newer release when the last check is older than fresh seconds, a minute
    // after launch at the earliest.
    private func checkUpdate(fresh: TimeInterval = UpdateSchedule.everySeconds) {
        guard engine.anchors.choices.checkUpdates, update == nil else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.checkedKey) as? Date
        guard UpdateSchedule.isDue(lastChecked: last, launched: launched, now: Date(), fresh: fresh) else {
            return
        }
        runUpdateCheck(say: false)
    }

    // checkUpdateNow looks for a newer release at once, even with the automatic check off, and says
    // what it found.
    func checkUpdateNow() {
        runUpdateCheck(say: true)
    }

    // runUpdateCheck asks GitHub for the latest release and keeps a newer one for the menu. With say
    // set it shows a banner for every outcome, including up to date and a failed request.
    private func runUpdateCheck(say: Bool) {
        let shown = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard let current = ReleaseVersion(shown) else { return }
        UserDefaults.standard.set(Date(), forKey: Self.checkedKey)
        let checker = UpdateChecker(client: URLSessionClient(), current: current)
        Task { @MainActor in
            do {
                self.update = try await checker.check()
            } catch {
                self.logger.notice("update check failed: \(error.localizedDescription, privacy: .public)")
                if say {
                    self.notify("Update check failed", "Moorings could not reach GitHub. Try again in a moment.")
                }
                return
            }
            guard say else { return }
            if let found = self.update {
                self.notify("Moorings \(found.tag) is out", "Click to open the release page.") {
                    NSWorkspace.shared.open(found.page)
                }
            } else {
                self.notify("Moorings is up to date", "Version \(shown) is the latest release.")
            }
        }
    }

    // showIcon shows the menu bar icon unless the choices hide it. Opening Moorings again while it
    // runs opens the settings, where the icon can be turned back on.
    func showIcon() {
        item.isVisible = !engine.anchors.choices.behavior.hideMenuBarIcon
    }

    // refreshShortcuts turns the shortcuts off while an app in the ignore list is in front.
    func refreshShortcuts() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        hotkeys.setEnabled(front.map { !engine.anchors.choices.ignores.contains($0) } ?? true)
    }

    // runLink runs the action a moorings://action?name= link asks for.
    private func runLink(_ url: URL) {
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?
            .value
        guard let name, engine.actions.runnable(name) else {
            logger.notice("a moorings link asked for unknown action \(name ?? "none", privacy: .public)")
            return
        }
        engine.actions.run(name)
    }

    // open opens the app with bundle the way a Dock click does, which launches it or asks a running
    // app with no window for a new one. A background open leaves the front app in front.
    func open(_ bundle: String, background: Bool, target: String? = nil) {
        _ = apps.open(bundle, background: background, target: target)
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
        logger.notice(
            "status: trusted=\(self.windows.trusted) build=\(build, privacy: .public) ultrawide=\(String(describing: screens.wide), privacy: .public) paused=\(self.engine.anchors.choices.paused) tap=\(self.tap.running) observed=\(self.events.observed) hotkeys=\(self.hotkeys.enabled)"
        )
        for (key, bundle) in engine.anchors.assignments().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let held = engine.anchors.slotWindows(key).map(String.init).joined(separator: ",")
            logger.notice(
                "slot \(key.rawValue, privacy: .public): \(bundle, privacy: .public) held=[\(held, privacy: .public)]")
        }
        for w in windows.scan(screens).windows {
            logger.notice(
                "window \(w.id) \(w.bundle, privacy: .public) frame=\(w.frame.description, privacy: .public) wide=\(w.onUltrawide) main=\(w.isMain) panel=\(w.isFilePanel) pinned=\(self.engine.anchors.pinned(w)) castOff=\(self.engine.anchors.isCastOff(w.id))"
            )
        }
        for line in windows.explain(screens) {
            logger.notice("scan \(line, privacy: .public)")
        }
    }

    // frontChanged notes the app that came to the front, drops its enhanced interface when the
    // choices ask, and turns the shortcuts off or on for it.
    @objc private func frontChanged(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            windows.lastFront = app.processIdentifier
            if windows.trusted,
                Behavior.disablesEnhancedUIOnActivation(
                    engine.anchors.choices.behavior.enhancedUI, bundle: app.bundleIdentifier,
                    assistive: NSWorkspace.shared.isVoiceOverEnabled)
            {
                Windows.dropEnhancedUI(app.processIdentifier)
            }
        }
        refreshShortcuts()
    }

    // screensChanged says how to anchor an app when the displays change and an ultrawide arrived.
    @objc private func screensChanged(_ note: Notification) {
        hintAnchor(Screens.current())
    }
}
