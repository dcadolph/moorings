import MooringsCore

// WorkspaceKeeper saves and recalls workspaces, recalls the one tied to the displays plugged in,
// places the first window of an app with a rule, and switches profiles.
public final class WorkspaceKeeper {
    // settleSeconds is how long the displays must stay unchanged before a recall.
    public static let settleSeconds = 1.5
    // waitSeconds is how long a recall waits for the window of an app it opened.
    public static let waitSeconds = 30.0
    // recheckSeconds is how long after a rule or a launch places a window it is checked again, for an
    // app that moves its own window once it shows.
    public static let recheckSeconds = 1.0

    // changed saves the choices after the keeper changed them, and lets the platform follow.
    public var changed: () -> Void = {}

    // Awaited is a window a recall is waiting for: the app it opened, the saved title and where it goes.
    struct Awaited {
        // bundle is the app opened.
        let bundle: String
        // title is the title the window was saved with.
        let title: String
        // frame is where the window goes.
        let frame: Frame
        // until is when the recall stops waiting.
        let until: Double
    }

    // platform reads and moves the windows and the displays, opens apps and logs.
    private let platform: Platform
    // settle waits for the displays to stay unchanged before a recall, a scheduler of its own.
    private let settle: any Scheduler
    // anchors is the layout the keeper reads and changes.
    private let anchors: Anchors
    // organizer gives the area organize actions and workspaces work in on each screen.
    private let organizer: Organizer
    // actions applies a rule's action to an app's first window.
    private let actions: ActionRunner
    // setup is the key of the displays last seen, so a display change recalls its workspace once. The
    // displays attached at launch count as handled.
    private var setup: String
    // awaited lists the windows recalls are waiting for.
    private var awaited: [Awaited] = []
    // present lists the apps with a window on screen at the last look, nil before the first look.
    private var present: Set<String>?
    // rechecks maps a window a rule or launch placed to the frame it was given and when to check it.
    private var rechecks: [WindowID: (frame: Frame, at: Double)] = [:]

    // init builds a keeper on platform and anchors, with the organizer's areas and the action runner.
    public init(platform: Platform, anchors: Anchors, organizer: Organizer, actions: ActionRunner) {
        self.platform = platform
        self.anchors = anchors
        self.organizer = organizer
        self.actions = actions
        settle = platform.timers.scheduler()
        setup = platform.screens.displaySetKey(platform.screens.current())
    }

    // now is the engine's clock.
    private var now: Double { platform.clock.now }

    // key is the display set key of the displays attached now.
    private var key: String { platform.screens.displaySetKey(platform.screens.current()) }

    // areas returns each display's full frame with the area organize actions work in on it.
    private func areas(_ screens: Screens) -> [ScreenAreas] {
        screens.full.indices.map { ScreenAreas(full: screens.full[$0], area: organizer.area(screens, $0)) }
    }

    // title returns a window's title, the first key a recall matches saved windows by, empty when it
    // has none.
    private func title(_ id: WindowID) -> String {
        platform.windows.title(id) ?? ""
    }

    // log writes what a workspace, rule or profile could not do.
    private func log(_ line: String) {
        platform.log.note(.organize, line)
    }

    // move places a window plainly, as a hold does.
    private func move(_ id: WindowID, to frame: Frame) {
        platform.windows.move(id, to: frame, from: nil, behavior: anchors.choices.behavior)
    }

    // freeWindows returns every window on any screen that is not pinned and not fullscreen,
    // front-most first.
    private func freeWindows(_ screens: Screens) -> [WindowInfo] {
        platform.windows.scan(screens, full: true).windows.filter { !anchors.pinned($0) && !$0.isFullScreen }
    }

    // saveWorkspace stores the layout in effect under name, keeping the display tie of a workspace
    // it replaces.
    public func saveWorkspace(_ name: String) {
        let windows = freeWindows(platform.screens.current()).map {
            SavedWindow(bundle: $0.bundle, title: title($0.id), frame: $0.frame)
        }
        let c = anchors.choices
        anchors.choices.workspaces[name] = Workspace(
            name: name, slots: c.slots, widths: anchors.widths,
            heights: anchors.heights, windows: windows,
            setup: c.workspaces[name]?.setup)
        changed()
    }

    // recall puts back the workspace saved as name and reports whether it existed. Apps it opens get
    // their windows placed once they show. Other windows whose app is not running, or whose display is
    // gone, stay where they are.
    @discardableResult
    public func recall(_ name: String) -> Bool {
        let opening = awaited.count
        guard let missed = place(name) else { return false }
        let opened = awaited.count - opening
        var text = missed > 0 ? "Recalled. \(missed) windows had no running app or display." : "Recalled."
        if opened > 0 {
            text += opened == 1 ? " Opening 1 app." : " Opening \(opened) apps."
        }
        platform.notifier.notify("Workspace \(name)", text)
        return true
    }

    // place puts back the workspace saved as name without a banner and returns how many of its
    // windows had no running app or display, or nil when paused or no workspace has that name.
    private func place(_ name: String) -> Int? {
        guard !anchors.choices.paused else { return nil }
        guard let ws = anchors.choices.workspaces[name] else {
            log("no workspace is named \(name)")
            return nil
        }
        anchors.choices.slots = ws.slots
        if let w = ws.widths, Layout.validSplit(w) {
            anchors.choices.widths = w
        }
        if let h = ws.heights, Layout.validTop(h.left), Layout.validTop(h.right) {
            anchors.choices.heights = h
        }
        let screens = platform.screens.current()
        let live = freeWindows(screens)
        let info = live.map { WorkspaceWindow(id: $0.id, bundle: $0.bundle, title: title($0.id), frame: $0.frame) }
        let areas = areas(screens)
        let matched = Workspaces.match(ws.windows, info)
        var missed = 0
        var opened: Set<String> = []
        for (i, saved) in ws.windows.enumerated() {
            if matched[i] == nil, let b = saved.launchBundle, !b.isEmpty,
                let target = Workspaces.fit(saved.frame, areas)
            {
                if opened.insert(b + "\u{0}" + (saved.openTarget ?? "")).inserted,
                    !platform.apps.open(b, background: true, target: saved.openTarget)
                {
                    log("workspace \(name): could not open \(b)")
                }
                awaited.append(
                    Awaited(
                        bundle: saved.bundle, title: saved.title, frame: target,
                        until: now + Self.waitSeconds))
                continue
            }
            guard let j = matched[i], let target = Workspaces.fit(saved.frame, areas) else {
                missed += 1
                continue
            }
            anchors.save(live[j])
            move(live[j].id, to: target)
        }
        if missed > 0 {
            log("workspace \(name): \(missed) windows had no running app or display")
        }
        changed()
        return missed
    }

    // delete removes the workspace saved as name.
    public func delete(_ name: String) {
        anchors.choices.workspaces[name] = nil
        changed()
    }

    // tied reports whether the workspace name comes back when the displays attached now are plugged
    // in.
    public func tied(_ name: String) -> Bool {
        let ws = anchors.choices.workspaces[name]
        return ws?.setup != nil && ws?.setup == key
    }

    // tie makes name come back when the displays attached now are plugged in, or unties it. One
    // workspace holds each display set.
    public func tie(_ name: String) {
        guard var ws = anchors.choices.workspaces[name] else { return }
        let now = key
        if ws.setup == now {
            ws.setup = nil
        } else {
            for (other, var o) in anchors.choices.workspaces where o.setup == now {
                o.setup = nil
                anchors.choices.workspaces[other] = o
            }
            ws.setup = now
        }
        anchors.choices.workspaces[name] = ws
        changed()
    }

    // screensChanged recalls workspaces once the displays have stayed unchanged for settleSeconds, so
    // a wake or a flapping dock that sends a burst of changes recalls once: each change replaces the
    // wait the one before set.
    public func screensChanged() {
        settle.schedule(at: now + Self.settleSeconds) { [weak self] in self?.recallForScreens() }
    }

    // recallForScreens recalls the workspace tied to the display set now plugged in, then each
    // workspace marked to come back on any display change, in name order.
    private func recallForScreens() {
        let now = key
        guard now != setup else { return }
        setup = now
        let tied = anchors.choices.workspaces.keys.sorted().first { anchors.choices.workspaces[$0]?.setup == now }
        if let tied {
            recall(tied)
        }
        for ws in Workspaces.recalling(anchors.choices.workspaces) where ws.name != tied {
            recall(ws.name)
        }
    }

    // waiting reports whether a recall is waiting for an app it opened to show a window, which may
    // come before the app takes an observer, so passes keep looking.
    public var waiting: Bool { !awaited.isEmpty }

    // deadlines returns when each placed window is due its second look.
    public func deadlines() -> [Double] {
        rechecks.values.map(\.at)
    }

    // seen looks at the windows on screen after each pass. A window a recall was waiting for goes where
    // the workspace saved it, matched by title first. Then, for each app whose first window just
    // appeared, its rule places that window. Apps already showing windows at the first look are not
    // new. A placed window is checked once more a moment later and put back if its app moved it.
    public func seen(_ list: [WindowInfo], screens: Screens) {
        let now = now
        let free = list.filter { !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0) }
        let bundles = Set(list.filter { !$0.isFilePanel }.map(\.bundle))
        defer { present = bundles }
        for (id, r) in rechecks where now >= r.at {
            rechecks[id] = nil
            if let f = platform.windows.frame(id), !Actions.near(f, r.frame, tolerance: Actions.tolerance) {
                move(id, to: r.frame)
            }
        }
        awaited.removeAll { $0.until < now }
        var claimed: Set<WindowID> = []
        var placedApps: Set<String> = []
        for (k, a) in awaited.enumerated().reversed() {
            let mine = free.filter { $0.bundle == a.bundle && !claimed.contains($0.id) }
            guard let w = mine.first(where: { title($0.id) == a.title }) ?? mine.first else { continue }
            claimed.insert(w.id)
            placedApps.insert(a.bundle)
            awaited.remove(at: k)
            anchors.save(w)
            move(w.id, to: a.frame)
            rechecks[w.id] = (a.frame, now + Self.recheckSeconds)
        }
        guard let before = present, !anchors.choices.paused else { return }
        for bundle in bundles.subtracting(before).subtracting(placedApps).sorted() {
            guard let rule = Workspaces.rule(bundle, anchors.choices.appRules),
                let w = free.first(where: { $0.bundle == bundle })
            else { continue }
            if let f = rule.frame {
                guard let target = Workspaces.fit(f, areas(screens)) else { continue }
                anchors.save(w)
                move(w.id, to: target)
                rechecks[w.id] = (target, now + Self.recheckSeconds)
            } else if let name = rule.action, actions.apply(name, to: w, screens: screens),
                let f = platform.windows.frame(w.id)
            {
                rechecks[w.id] = (f, now + Self.recheckSeconds)
            }
            log("rule for \(bundle) placed its first window")
        }
    }

    // saveProfile saves the current shortcuts, snapping, behavior, menu and rules as the profile
    // name, keeping the workspace group of a profile already saved under it, and marks it active.
    public func saveProfile(_ name: String) {
        let settings = anchors.choices.profileSettings()
        if let i = anchors.choices.profiles.firstIndex(where: { $0.name == name }) {
            anchors.choices.profiles[i].settings = settings
        } else {
            anchors.choices.profiles.append(Profile(name: name, settings: settings))
        }
        anchors.choices.activeProfile = name
        changed()
    }

    // applyProfile switches to the profile saved as name: its settings take effect, hotkeys
    // follow, and its workspaces are recalled in order. Anchored apps and strip sizes stay.
    @discardableResult
    public func applyProfile(_ name: String) -> Bool {
        guard let profile = anchors.choices.profiles.first(where: { $0.name == name }) else {
            log("no profile is named \(name)")
            return false
        }
        anchors.choices = anchors.choices.applying(profile)
        changed()
        let paused = anchors.choices.paused && !profile.workspaces.isEmpty
        var recalled: [String] = []
        var missing: [String] = []
        var missed = 0
        for ws in profile.workspaces where !paused {
            if let n = place(ws) {
                recalled.append(ws)
                missed += n
            } else {
                missing.append(ws)
            }
        }
        platform.notifier.notify(
            "Profile \(name)",
            Profiles.switchMessage(recalled: recalled, missing: missing, missed: missed, paused: paused))
        return true
    }
}
