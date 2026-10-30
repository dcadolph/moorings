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
    // attemptKey holds the tag an install swapped in, until the next launch reads whether it started.
    static let attemptKey = "updateAttempt"
    // failedKey lists the tags that were swapped in and never started, so none is fetched again.
    static let failedKey = "updateFailed"
    // trustedKey records whether Accessibility was granted when an install began.
    static let trustedKey = "updateTrusted"
    // stagedKey holds the tag of a verified update that found no quiet moment before Quit.
    static let stagedKey = "updateStaged"
    // toldKey records that Moorings said once it now installs updates on its own.
    static let toldKey = "autoUpdateTold"
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
    // updater checks for, verifies and installs newer releases.
    lazy var updater = makeUpdater()
    // marker records each launch, so the relaunch helper can roll back a build that never starts.
    let marker = LaunchMarker(
        folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moorings", isDirectory: true))
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
    // saveFailureTold is whether this launch has already told the owner a save failed.
    var saveFailureTold = false
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
    // shownMark is the trust and pause state the menu bar icon last drew.
    private var shownMark: (trusted: Bool, paused: Bool)?
    // sinking plays the quit animation.
    private let sinking = Sinking()

    // version is the running short version, empty for a build without one.
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }
    // build is the running build number, empty for a build without one.
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    // updateCache is the folder update downloads are staged in.
    static let updateCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.dcadolph.moorings", isDirectory: true)
        .appendingPathComponent("update", isDirectory: true)

    // now returns the time in seconds since boot.
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    // applicationWillFinishLaunching records the launch under way, and says when the last run of this
    // build ended without Quit.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if marker.begin(build: Self.build, pid: ProcessInfo.processInfo.processIdentifier) {
            logger.notice("previous run ended without quit")
        }
    }

    // applicationDidFinishLaunching builds the menu, subscribes to events, and runs the first pass.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Windows.timeout)
        if installer.offerMove() {
            return
        }
        installer.offerTrash()
        if installStaged() {
            return
        }
        let lost = settleAttempt()
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
        events.turned = { [weak self] in self?.showMark() }
        engine.observers.passed = { [weak self] _, _ in self?.showMark() }
        engine.observers.saveFailed = { [weak self] _ in self?.saveFailed() }
        showMark()
        if !windows.trusted, lost {
            logger.notice("Accessibility was lost across an update: windows will not move")
            notify(
                "Moorings lost its Accessibility grant",
                "Click here to open Privacy & Security, then turn on Moorings again."
            ) { NSWorkspace.shared.open(Self.accessibilityPane) }
        } else if !windows.trusted {
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
        marker.finish(build: Self.build)
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
        sinking.play(over: rect, appearance: button.effectiveAppearance) {
            NSApp.terminate(nil)
        }
    }

    // applicationWillTerminate shuts the engine down, which puts stashed windows back, so none is left
    // parked off screen.
    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
        marker.quit()
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
            case "update": updateNow()
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
                engine.actions.fill(w, screens: screens)
            } else {
                engine.actions.unfill(id)
            }
        }
        engine.channelCycle.sync()
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

    // saveFailed tells the owner once per launch that the settings could not be written. A click opens
    // the settings.
    func saveFailed() {
        guard !saveFailureTold else { return }
        saveFailureTold = true
        notify("Moorings could not save your settings", "Click to open the settings.") { [weak self] in
            self?.settings.show()
        }
    }

    // notify shows a banner in the harbor palette. A click on it runs action.
    func notify(_ title: String, _ body: String, action: (@MainActor () -> Void)? = nil) {
        logger.notice("banner: \(body, privacy: .public)")
        banner.show(title, body, palette: .harbor, action: action)
    }

    // showMark shows a warning mark on the menu bar icon while Accessibility is missing, and the
    // sailboat with its sails lowered while paused. It sets the image only when either changed.
    private func showMark() {
        guard !quitting else { return }
        let state = (trusted: windows.trusted, paused: engine.anchors.choices.paused)
        guard shownMark.map({ $0 != state }) ?? true else { return }
        shownMark = state
        item.button?.image =
            state.trusted
            ? Mark.image(paused: state.paused)
            : NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Moorings")
    }

    // releaseMessage says once that moorings was updated, on the first launch of a new version.
    private func releaseMessage() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let last = UserDefaults.standard.string(forKey: Self.versionKey)
        UserDefaults.standard.set(version, forKey: Self.versionKey)
        guard let last, last != version, !version.isEmpty else { return }
        let choices = engine.anchors.choices
        if !UserDefaults.standard.bool(forKey: Self.toldKey), choices.checkUpdates, choices.installUpdates {
            UserDefaults.standard.set(true, forKey: Self.toldKey)
            notify(
                "Moorings updated to v\(version)",
                "Moorings now installs updates on its own. Click to change that in Settings."
            ) { [weak self] in self?.settings.show() }
            return
        }
        notify("Moorings updated to v\(version)", "Updated from \(last). Click to see what is new.") {
            NSWorkspace.shared.open(Self.releasesPage.appendingPathComponent("tag/v\(version)"))
        }
    }

    // checkUpdate looks for a newer release when the last check is older than fresh seconds, a minute
    // after launch at the earliest.
    private func checkUpdate(fresh: TimeInterval = UpdateSchedule.everySeconds) {
        guard engine.anchors.choices.checkUpdates, !updater.state.busy else { return }
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

    // runUpdateCheck asks GitHub for the latest release, and with installs on fetches and verifies it.
    // With say set it shows a banner for every outcome, including up to date and a failed request.
    private func runUpdateCheck(say: Bool) {
        guard ReleaseVersion(Self.version) != nil else { return }
        UserDefaults.standard.set(Date(), forKey: Self.checkedKey)
        let choices = engine.anchors.choices
        let install = choices.checkUpdates && choices.installUpdates
        Task { @MainActor in
            let found: ReleaseInfo?
            do {
                found = try await self.updater.check(automatic: choices.checkUpdates, install: install, forced: say)
            } catch {
                self.logger.notice("update check failed: \(error.localizedDescription, privacy: .public)")
                if say {
                    self.notify("Update check failed", "Moorings could not reach GitHub. Try again in a moment.")
                }
                return
            }
            guard say else { return }
            guard let found else {
                self.notify("Moorings is up to date", "Version \(Self.version) is the latest release.")
                return
            }
            if case .verified = self.updater.state {
                self.notify("Moorings \(found.tag) is ready", "It installs the next time you pause for a moment.")
            } else {
                self.notify("Moorings \(found.tag) is out", "Click to open the release page.") {
                    NSWorkspace.shared.open(found.page)
                }
            }
        }
    }

    // updateNow checks, verifies and installs the latest release at once, without waiting for a quiet
    // moment, and logs each step. It is the moorings://update link.
    private func updateNow() {
        logger.notice("update: asked by link")
        guard ReleaseVersion(Self.version) != nil else {
            logger.notice("update: this build has no release version")
            return
        }
        Task { @MainActor in
            do {
                let found = try await self.updater.check(automatic: true, install: true, forced: true)
                if found == nil {
                    self.logger.notice("update: \(Self.version, privacy: .public) is the latest release")
                }
            } catch {
                self.logger.notice("update: check failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            self.updater.installNow()
        }
    }

    // makeUpdater builds the updater for the running bundle, skipping tags that failed to start.
    private func makeUpdater() -> Updater {
        let current = ReleaseVersion(Self.version) ?? ReleaseVersion("0.0.0")!
        let failed = UserDefaults.standard.stringArray(forKey: Self.failedKey) ?? []
        let u = Updater(
            client: URLSessionClient(), downloader: URLSessionDownloader(),
            trust: CodeTrustCheck(current: current, running: CodeTrust.runningRequirement()), current: current,
            bundle: Installer.originalURL(Bundle.main.bundleURL), cache: Self.updateCache, skip: Set(failed))
        u.log = { [logger] line in logger.notice("update: \(line, privacy: .public)") }
        u.changed = { [weak self] in
            guard let self else { return }
            if case .verified(let tag) = self.updater.state {
                UserDefaults.standard.set(tag, forKey: Self.stagedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.stagedKey)
            }
        }
        u.quiet = { [weak self] in self?.quietMoment() ?? false }
        u.install = { [weak self] staged, tag in self?.installUpdate(staged, tag: tag) }
        return u
    }

    // quietMoment reports whether a relaunch would interrupt nothing: no window held, no grid or strip
    // editor up, no Moorings window or alert open, and no input for the last 30 seconds.
    private func quietMoment() -> Bool {
        let anyInput = CGEventType(rawValue: ~0)!
        return !engine.mouseHeld && !engine.gridPicker.showing && !strips.showing
            && !NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            && CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= 30
    }

    // installUpdate swaps the staged bundle in, starts the helper that relaunches it and rolls back a
    // build that never starts, and quits through the same path as Quit.
    private func installUpdate(_ staged: URL, tag: String) {
        let bundle = updater.bundle
        let previous = marker.folder.appendingPathComponent("previous", isDirectory: true)
            .appendingPathComponent(Updater.appName)
        let build =
            (NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))?["CFBundleVersion"]
                as? String) ?? ""
        let backup: URL
        do {
            backup = try Updater.swap(bundle: bundle, staged: staged, previous: previous)
        } catch {
            logger.error("update: swap failed: \(error.localizedDescription, privacy: .public)")
            updater.refuse(.location, tag)
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(tag, forKey: Self.attemptKey)
        defaults.set(windows.trusted, forKey: Self.trustedKey)
        defaults.removeObject(forKey: Self.stagedKey)
        var plan = Relaunch.Plan(bundle: bundle)
        plan.previous = backup
        plan.failed = Self.updateCache.deletingLastPathComponent().appendingPathComponent("failed-\(tag).app")
        plan.marker = marker.marker
        plan.build = build
        do {
            try Relaunch.start(plan)
        } catch {
            logger.error("update: relaunch failed: \(error.localizedDescription, privacy: .public)")
        }
        logger.notice("update: relaunch into \(tag, privacy: .public) build \(build, privacy: .public)")
        NSApp.terminate(nil)
    }

    // installStaged installs a verified update that found no quiet moment before the last Quit,
    // verifying it again first, and reports whether Moorings is quitting to relaunch it.
    private func installStaged() -> Bool {
        let defaults = UserDefaults.standard
        guard let tag = defaults.string(forKey: Self.stagedKey) else { return false }
        defaults.removeObject(forKey: Self.stagedKey)
        let choices = engine.anchors.choices
        let staged = Self.updateCache.appendingPathComponent(tag, isDirectory: true)
            .appendingPathComponent("unpacked", isDirectory: true).appendingPathComponent(Updater.appName)
        guard choices.checkUpdates, choices.installUpdates, let version = ReleaseVersion(tag),
            let current = ReleaseVersion(Self.version), version > current,
            FileManager.default.fileExists(atPath: staged.path)
        else { return false }
        let name = String(tag.dropFirst(tag.hasPrefix("v") ? 1 : 0))
        if let step = updater.trust.verify(bundle: staged, version: name) {
            logger.notice("update: staged \(tag, privacy: .public) refused at \(step.rawValue, privacy: .public)")
            return false
        }
        logger.notice("update: installing \(tag, privacy: .public) staged before the last quit")
        installUpdate(staged, tag: tag)
        return true
    }

    // settleAttempt reads how the last install went: a tag this build is not at never started, so
    // it is never fetched again, and the owner is told. It reports whether Accessibility was granted
    // before the install, so a loss can be named.
    private func settleAttempt() -> Bool {
        let defaults = UserDefaults.standard
        guard let tag = defaults.string(forKey: Self.attemptKey) else { return false }
        let wasTrusted = defaults.bool(forKey: Self.trustedKey)
        defaults.removeObject(forKey: Self.attemptKey)
        defaults.removeObject(forKey: Self.trustedKey)
        if ReleaseVersion(tag) != ReleaseVersion(Self.version) {
            var failed = defaults.stringArray(forKey: Self.failedKey) ?? []
            failed.append(tag)
            defaults.set(failed, forKey: Self.failedKey)
            logger.error("update: \(tag, privacy: .public) did not start, back on \(Self.version, privacy: .public)")
            notify(
                "Moorings \(tag) did not start",
                "Moorings went back to v\(Self.version) and will not try \(tag) again. Click for the release page."
            ) { NSWorkspace.shared.open(Self.releasesPage) }
            return false
        }
        return wasTrusted
    }

    // showIcon shows the menu bar icon unless the choices hide it. Opening Moorings again while it
    // runs opens the settings, where the icon can be turned back on.
    func showIcon() {
        item.isVisible = !engine.anchors.choices.behavior.hideMenuBarIcon
    }

    // refreshShortcuts turns the shortcuts off while an app in the ignore list is in front, and the
    // channel cycle's claim with them.
    func refreshShortcuts() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        hotkeys.setEnabled(front.map { !engine.anchors.choices.ignores.contains($0) } ?? true)
        engine.channelCycle.sync()
    }

    // runLink runs the action a moorings://action?name= link asks for.
    private func runLink(_ url: URL) {
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?
            .value
        guard let name, engine.actions.runnable(name) else {
            logger.notice("a moorings link asked for unknown action \(name ?? "none", privacy: .public)")
            return
        }
        if let refused = engine.actions.linkRefused(name) {
            logger.notice(
                "a moorings link asked for \(refused, privacy: .public): closing actions run only from shortcuts and the menu"
            )
            notify("Moorings", "A link asked to \(refused). Closing actions run only from shortcuts and the menu.")
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
        logger.notice("status: update=\(self.updater.state.status, privacy: .public)")
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
