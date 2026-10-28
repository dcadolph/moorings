import AppKit
import ServiceManagement
import os

import MooringsCore
import MooringsEngine

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
    private lazy var watcher = Watcher { [weak self] el, note in self?.windowEvent(el, note) }
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
    // update is a newer release found by the update check, nil when none.
    var update: ReleaseInfo?
    // launched is when moorings started.
    private let launched = Date()
    // wasTrusted is the Accessibility state at the last tick, to catch the grant.
    private var wasTrusted = true
    // updateTimer runs the update check.
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
    // platform is what the engine reads and drives on the Mac.
    lazy var platform = Platform(
        windows: windows, screens: MacScreens(), overlay: Footprint(), notifier: MacNotifier(banner),
        clock: MacClock(), scheduler: MacScheduler(), store: DefaultsStore(key: Self.choicesKey),
        warpCursor: { p in CGWarpMouseCursorPosition(CGPoint(x: p.x, y: p.y)) }
    )
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
    // fullWoke is when the last wake came that named no app, so every app is read again.
    private var fullWoke = 0.0
    // appWoke holds when each app last sent a window event or had a window moved by an action.
    private var appWoke: [pid_t: Double] = [:]
    // echoes holds the frame an action read back after moving each window, with when it did, so the
    // window's own move events and the pass after read nothing the action already read.
    private var echoes: [WindowID: (frame: Frame, at: Double)] = [:]
    // lastFull is when the last pass that read every app ran.
    private var lastFull = -Double.infinity
    // lastApps is when a full pass last asked every running app for its kind, nil before the first.
    private var lastApps: Double?
    // lastRead holds each window id the last pass read, front-most first.
    private var lastRead: [WindowID] = []
    // lastFrames holds the frames that match lastRead.
    private var lastFrames: [Frame] = []
    // still reports whether the last pass read what the pass before it read and moved nothing.
    private var still = false
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
            if self.strips.showing {
                self.strips.key(tag)
            } else if self.gridPicker.showing {
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

    // menuNeedsUpdate rebuilds the menu from the current state each time it opens, and checks for a
    // release when the last check is over an hour old so the next open can offer it.
    func menuNeedsUpdate(_ menu: NSMenu) {
        checkUpdate(fresh: UpdateSchedule.menuSeconds)
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

    // windowEvent wakes the passes for a window event a pass acts on, and drops the moves, resizes
    // and births of windows no scan keeps. A kept window's event wakes without asking its kind, any
    // other event wakes without reading the window at all, and an event names its app so the passes
    // read only that app.
    private func windowEvent(_ el: AXUIElement, _ note: String) {
        let id = Pace.geometryEvents.contains(note) ? Windows.id(el) : nil
        guard Pace.wakes(note, kept: windows.keeps(id), eligible: Windows.eligible(el)) else { return }
        if note == kAXWindowMovedNotification || note == kAXWindowResizedNotification, let id,
           let echo = echoes[id], Self.now - echo.at < Pace.settleSeconds
        {
            poll()
            return
        }
        if let pid = Windows.pid(el) {
            wake(pid)
        } else {
            wake()
        }
    }

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle, and
    // read every app.
    func wake() {
        fullWoke = Self.now
        poll()
    }

    // wake marks the windows of the app with pid as changing, so passes run every Pace.pollSeconds
    // until they settle, and read that app.
    func wake(_ pid: pid_t) {
        appWoke[pid] = Self.now
        poll()
    }

    // echo records frame as where an action just read back the window with id after moving it, and
    // runs passes until windows settle. The window's own move events then only poll, and the pass
    // after reads its app only when the window server lists it somewhere else.
    func echo(_ id: WindowID, at frame: Frame) {
        echoes[id] = (frame, Self.now)
        poll()
    }

    // landed records frame as the last frame read for the window with id, which an action just read
    // back after moving it, so the pass after reads it at rest and ends the polling.
    func landed(_ id: WindowID, at frame: Frame) {
        if let i = lastRead.firstIndex(of: id) {
            lastFrames[i] = frame
        }
    }

    // poll runs passes every Pace.pollSeconds from now until windows settle.
    private func poll() {
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
        schedule(Pace.next(now: t, woke: woke, busy: busy, deadlines: anchors.deadlines() + organizer.deadlines(),
                           still: still))
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

    // tick catches an Accessibility grant or loss, then runs the pass that was due. A loss tears
    // down the tap and every observer and a grant builds them again, since what was made under the
    // old grant may never deliver another event.
    private func tick() {
        if windows.trusted != wasTrusted {
            wasTrusted = windows.trusted
            showTrust()
            if wasTrusted {
                logger.notice("Accessibility is on: starting the tap and watching every app again")
                tap.start()
                watcher.watch(Self.regularApps())
                notify("Moorings is ready", "Accessibility is on. Anchored apps take their slots now.")
            } else {
                logger.notice("Accessibility is off: stopping the tap and every observer")
                tap.stop()
                watcher.reset()
            }
        }
        moor()
    }

    // moor runs one pass and applies its moves. The first pass after launch opens the anchored apps
    // that have no window, in the background.
    func moor() {
        still = false
        defer { pace() }
        guard windows.trusted else { return }
        if !tap.running {
            tap.start()
        }
        let screens = Screens.current()
        let t = Self.now
        appWoke = appWoke.filter { t - $0.value < Pace.settleSeconds }
        echoes = echoes.filter { t - $0.value.at < Pace.settleSeconds }
        let echoed = echoes.mapValues(\.frame)
        let forced = !started || watcher.waiting || organizer.waiting || t < launching
        let (list, focused) = windows.scan(screens) { [self] listed, previous, slow, front in
            PassPlan.plan(now: t, forced: forced, lastFull: lastFull, fullWoke: fullWoke, woke: appWoke,
                          listed: listed, previous: previous, slow: slow, front: front, echoes: echoed)
        }
        logger.debug("pass \(self.windows.lastPlan == .full ? "full" : "apps", privacy: .public) read \(self.windows.scanned.count)")
        if windows.lastPlan == .full {
            lastFull = t
            if PassPlan.refreshesApps(now: t, last: lastApps, waiting: watcher.waiting) {
                lastApps = t
                watcher.watch(Self.regularApps())
                let alive = Windows.alive()
                anchors.prune(alive: alive)
                actions.prune(alive: alive)
                stasher.prune(alive: alive)
            }
        }
        watcher.watchClosing(windows.elements)
        if anchors.hasCastOff || !anchors.stashed.isEmpty {
            anchors.prune(alive: Windows.alive())
        }
        let scene = Scene(screen: screens.wide, windows: list, focused: focused?.id,
                          mouseHeld: NSEvent.pressedMouseButtons & 1 != 0 || hover.active, now: Self.now)
        let moves = anchors.moor(scene)
        for move in moves {
            apply(move, bundle: list.first { $0.id == move.id }?.bundle ?? "?")
        }
        let read = list.map(\.id)
        let frames = list.map(\.frame)
        still = moves.isEmpty && !scene.mouseHeld && read == lastRead && frames == lastFrames
        lastRead = read
        lastFrames = frames
        organizer.seen(list, screens: screens)
        tiler.pass(list, screens: screens, mouseHeld: scene.mouseHeld)
        for id in anchors.justReleased {
            let w = list.first { $0.id == id }
            let now = w.map { "\($0.frame)" } ?? "?"
            let back = anchors.readBack(id).map { "\($0)" } ?? "?"
            let asked = anchors.target(id).map { "\($0)" } ?? "?"
            logger.notice("""
                window \(id) was moved by hand: released at \(now, privacy: .public), \
                read back \(back, privacy: .public), asked \(asked, privacy: .public)
                """)
            let name = w.map { appName($0.bundle) } ?? "The window"
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
    // where it landed, and moves it once more when it kept a larger size than it was given. It logs
    // a move whose window could not be read back or landed away from the target.
    private func apply(_ move: Move, bundle: String) {
        if move.exitFullScreen {
            windows.exitFullScreen(move.id)
            return
        }
        windows.move(move.id, to: move.frame)
        let asked = "\(move.frame)"
        guard let got = windows.frame(move.id) else {
            logger.notice("""
                window \(move.id) \(bundle, privacy: .public): move to \(asked, privacy: .public) unreadable
                """)
            anchors.unread(move)
            return
        }
        guard let again = anchors.landed(move, got: got) else {
            if !Actions.near(got, move.frame, tolerance: Anchors.tolerance) {
                let landed = "\(got)"
                logger.notice("""
                    window \(move.id) \(bundle, privacy: .public): move to \(asked, privacy: .public) refused, \
                    landed at \(landed, privacy: .public)
                    """)
            }
            return
        }
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

    // checkUpdate looks for a newer release when the last check is older than fresh seconds, a minute
    // after launch at the earliest.
    private func checkUpdate(fresh: TimeInterval = UpdateSchedule.everySeconds) {
        guard anchors.choices.checkUpdates, update == nil else { return }
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
        logger.notice("status: trusted=\(self.windows.trusted) build=\(build, privacy: .public) ultrawide=\(String(describing: screens.wide), privacy: .public) paused=\(self.anchors.choices.paused) tap=\(self.tap.running) observed=\(self.watcher.count) hotkeys=\(self.hotkeys.enabled)")
        for (key, bundle) in anchors.assignments().sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let held = anchors.slotWindows(key).map(String.init).joined(separator: ",")
            logger.notice("slot \(key.rawValue, privacy: .public): \(bundle, privacy: .public) held=[\(held, privacy: .public)]")
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

// MacClock is the Mac Clock: seconds since boot, the clock the delegate's own timestamps use.
final class MacClock: Clock {
    // now is the system uptime in seconds.
    var now: Double { ProcessInfo.processInfo.systemUptime }
}

// MacScheduler is the Mac Scheduler: one main run loop timer, replaced on each schedule.
@MainActor
final class MacScheduler: @preconcurrency Scheduler {
    // timer is the pending timer, nil when nothing is pending.
    private var timer: Timer?
    // work is the pending work, nil when nothing is pending.
    private var work: (() -> Void)?

    // schedule runs work at uptime at on the main thread, replacing any pending work.
    func schedule(at: Double, _ work: @escaping () -> Void) {
        timer?.invalidate()
        self.work = work
        let wait = max(0, at - ProcessInfo.processInfo.systemUptime)
        timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    // cancel drops the pending work.
    func cancel() {
        timer?.invalidate()
        timer = nil
        work = nil
    }

    // fire runs the pending work once, clearing it first so the work may schedule more.
    private func fire() {
        let w = work
        timer = nil
        work = nil
        w?()
    }
}

// DefaultsStore is the Mac ChoicesStore: the encoded choices under one user defaults key.
final class DefaultsStore: ChoicesStore {
    // key is the defaults key the choices live under.
    private let key: String

    // init keeps the choices under key.
    init(key: String) {
        self.key = key
    }

    // load decodes the saved choices, or the defaults when none are saved.
    func load() -> Choices {
        Choices.decode(UserDefaults.standard.data(forKey: key) ?? Data())
    }

    // save encodes choices under the key.
    func save(_ choices: Choices) throws {
        UserDefaults.standard.set(try Choices.encode(choices), forKey: key)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
