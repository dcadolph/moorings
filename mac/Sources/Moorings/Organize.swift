import AppKit
import os

import MooringsCore

// WorkspaceKeeper saves and recalls workspaces, applies app rules and switches profiles.
@MainActor
final class WorkspaceKeeper {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes what a workspace, rule or profile could not do.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "organize")
    // setup is the signature of the displays last seen, so a display change recalls its workspace
    // once. The displays attached at launch count as handled.
    private var setup: String
    // changes counts display changes, so only the last of a burst recalls once the displays settle.
    private var changes = 0
    // settleSeconds is how long the displays must stay unchanged before a recall.
    private static let settleSeconds = 1.5
    // waitSeconds is how long a recall waits for the window of an app it opened.
    static let waitSeconds = 30.0
    // recheckSeconds is how long after a rule or a launch places a window it is checked again, for an
    // app that moves its own window once it shows.
    static let recheckSeconds = 1.0

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

    // awaited lists the windows recalls are waiting for.
    private var awaited: [Awaited] = []
    // present lists the apps with a window on screen at the last look, nil before the first look.
    private var present: Set<String>?
    // rechecks maps a window a rule or launch placed to the frame it was given and when to check it.
    private var rechecks: [WindowID: (frame: Frame, at: Double)] = [:]

    // init builds a keeper for app.
    init(app: AppDelegate) {
        self.app = app
        setup = Workspaces.signature(Screens.current().full)
    }

    // anchors is the layout the organizer reads and changes.
    private var anchors: Anchors { app.anchors }

    // freeWindows returns every window on any screen that is not pinned and not fullscreen,
    // front-most first.
    private func freeWindows(_ screens: Screens) -> [WindowInfo] {
        app.windows.scan(screens).windows.filter { !anchors.pinned($0) && !$0.isFullScreen }
    }

    // saveWorkspace stores the layout in effect under name, keeping the display tie of a workspace
    // it replaces.
    func saveWorkspace(_ name: String) {
        let screens = Screens.current()
        let windows = freeWindows(screens).map {
            SavedWindow(bundle: $0.bundle, title: app.windows.title($0.id), frame: $0.frame)
        }
        let c = anchors.choices
        anchors.choices.workspaces[name] = Workspace(name: name, slots: c.slots, widths: anchors.widths,
                                                     heights: anchors.heights, windows: windows,
                                                     setup: c.workspaces[name]?.setup)
        app.save()
    }

    // recall puts back the workspace saved as name and reports whether it existed. Apps it opens get
    // their windows placed once they show. Other windows whose app is not running, or whose display is
    // gone, stay where they are.
    @discardableResult
    func recall(_ name: String) -> Bool {
        let opening = awaited.count
        guard let missed = place(name) else { return false }
        let opened = awaited.count - opening
        var text = missed > 0 ? "Recalled. \(missed) windows had no running app or display." : "Recalled."
        if opened > 0 {
            text += opened == 1 ? " Opening 1 app." : " Opening \(opened) apps."
        }
        app.notify("Workspace \(name)", text)
        return true
    }

    // place puts back the workspace saved as name without a banner and returns how many of its
    // windows had no running app or display, or nil when paused or no workspace has that name.
    private func place(_ name: String) -> Int? {
        guard !anchors.choices.paused else { return nil }
        guard let ws = anchors.choices.workspaces[name] else {
            logger.notice("no workspace is named \(name, privacy: .public)")
            return nil
        }
        anchors.choices.slots = ws.slots
        if let w = ws.widths, Layout.validSplit(w) {
            anchors.choices.widths = w
        }
        if let h = ws.heights, Layout.validTop(h.left), Layout.validTop(h.right) {
            anchors.choices.heights = h
        }
        let screens = Screens.current()
        let live = freeWindows(screens)
        let info = live.map { WorkspaceWindow(id: $0.id, bundle: $0.bundle, title: app.windows.title($0.id), frame: $0.frame) }
        let areas = screens.full.indices.map { ScreenAreas(full: screens.full[$0], area: app.organizer.area(screens, $0)) }
        let matched = Workspaces.match(ws.windows, info)
        var missed = 0
        var opened: Set<String> = []
        for (i, saved) in ws.windows.enumerated() {
            if matched[i] == nil, let b = saved.launchBundle, !b.isEmpty, let target = Workspaces.fit(saved.frame, areas) {
                if opened.insert(b + "\u{0}" + (saved.openTarget ?? "")).inserted {
                    app.open(b, background: true, target: saved.openTarget)
                }
                awaited.append(Awaited(bundle: saved.bundle, title: saved.title, frame: target,
                                       until: AppDelegate.now + Self.waitSeconds))
                continue
            }
            guard let j = matched[i], let target = Workspaces.fit(saved.frame, areas) else {
                missed += 1
                continue
            }
            anchors.save(live[j])
            app.windows.move(live[j].id, to: target)
        }
        if missed > 0 {
            logger.notice("workspace \(name, privacy: .public): \(missed) windows had no running app or display")
        }
        app.save()
        return missed
    }

    // delete removes the workspace saved as name.
    func delete(_ name: String) {
        anchors.choices.workspaces[name] = nil
        app.save()
    }

    // tied reports whether the workspace name comes back when the displays attached now are plugged
    // in.
    func tied(_ name: String) -> Bool {
        let ws = anchors.choices.workspaces[name]
        return ws?.setup != nil && ws?.setup == Workspaces.signature(Screens.current().full)
    }

    // tie makes name come back when the displays attached now are plugged in, or unties it. One
    // workspace holds each display setup.
    func tie(_ name: String) {
        guard var ws = anchors.choices.workspaces[name] else { return }
        let now = Workspaces.signature(Screens.current().full)
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
        app.save()
    }

    // screensChanged recalls workspaces once the displays have stayed unchanged for settleSeconds, so
    // a wake or a flapping dock that sends a burst of changes recalls once.
    func screensChanged() {
        changes += 1
        let change = changes
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
            guard let self, change == changes else { return }
            recallForScreens()
        }
    }

    // recallForScreens recalls the workspace tied to the display setup now plugged in, then each
    // workspace marked to come back on any display change, in name order.
    private func recallForScreens() {
        let now = Workspaces.signature(Screens.current().full)
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
    var waiting: Bool { !awaited.isEmpty }

    // deadlines returns when each placed window is due its second look.
    func deadlines() -> [Double] {
        rechecks.values.map(\.at)
    }

    // seen looks at the windows on screen after each pass. A window a recall was waiting for goes where
    // the workspace saved it, matched by title first. Then, for each app whose first window just
    // appeared, its rule places that window. Apps already showing windows at the first look are not
    // new. A placed window is checked once more a moment later and put back if its app moved it.
    func seen(_ list: [WindowInfo], screens: Screens) {
        let now = AppDelegate.now
        let free = list.filter { !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0) }
        let bundles = Set(list.filter { !$0.isFilePanel }.map(\.bundle))
        defer { present = bundles }
        for (id, r) in rechecks where now >= r.at {
            rechecks[id] = nil
            if let f = app.windows.frame(id), !Actions.near(f, r.frame, tolerance: Actions.tolerance) {
                app.windows.move(id, to: r.frame)
            }
        }
        awaited.removeAll { $0.until < now }
        var claimed: Set<WindowID> = []
        var placedApps: Set<String> = []
        for (k, a) in awaited.enumerated().reversed() {
            let mine = free.filter { $0.bundle == a.bundle && !claimed.contains($0.id) }
            guard let w = mine.first(where: { app.windows.title($0.id) == a.title }) ?? mine.first else { continue }
            claimed.insert(w.id)
            placedApps.insert(a.bundle)
            awaited.remove(at: k)
            anchors.save(w)
            app.windows.move(w.id, to: a.frame)
            rechecks[w.id] = (a.frame, now + Self.recheckSeconds)
        }
        guard let before = present, !anchors.choices.paused else { return }
        for bundle in bundles.subtracting(before).subtracting(placedApps).sorted() {
            guard let rule = Workspaces.rule(bundle, anchors.choices.appRules),
                  let w = free.first(where: { $0.bundle == bundle })
            else { continue }
            if let f = rule.frame {
                let areas = screens.full.indices.map { ScreenAreas(full: screens.full[$0], area: app.organizer.area(screens, $0)) }
                guard let target = Workspaces.fit(f, areas) else { continue }
                anchors.save(w)
                app.windows.move(w.id, to: target)
                rechecks[w.id] = (target, now + Self.recheckSeconds)
            } else if let name = rule.action, app.actions.apply(name, to: w, screens: screens),
                      let f = app.windows.frame(w.id) {
                rechecks[w.id] = (f, now + Self.recheckSeconds)
            }
            logger.notice("rule for \(bundle, privacy: .public) placed its first window")
        }
    }

    // saveProfile saves the current shortcuts, snapping, behavior, menu and rules as the profile
    // name, keeping the workspace group of a profile already saved under it, and marks it active.
    func saveProfile(_ name: String) {
        let settings = anchors.choices.profileSettings()
        if let i = anchors.choices.profiles.firstIndex(where: { $0.name == name }) {
            anchors.choices.profiles[i].settings = settings
        } else {
            anchors.choices.profiles.append(Profile(name: name, settings: settings))
        }
        anchors.choices.activeProfile = name
        app.save()
    }

    // applyProfile switches to the profile saved as name: its settings take effect, hotkeys
    // follow, and its workspaces are recalled in order. Anchored apps and strip sizes stay.
    @discardableResult
    func applyProfile(_ name: String) -> Bool {
        guard let profile = anchors.choices.profiles.first(where: { $0.name == name }) else {
            logger.notice("no profile is named \(name, privacy: .public)")
            return false
        }
        anchors.choices = anchors.choices.applying(profile)
        app.save()
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
        app.notify("Profile \(name)",
                   Profiles.switchMessage(recalled: recalled, missing: missing, missed: missed, paused: paused))
        return true
    }

    // askName asks for a name, nil when canceled or empty. The default wording names a workspace.
    static func askName(
        _ title: String = "Save workspace",
        _ info: String = "Name this layout: the slots, widths, heights and where each free window sits."
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// Tiler keeps the free windows of each display in the tiling mode's layout as windows come and go,
// and runs the tiling actions. A window the owner drags or resizes floats until a mode is chosen
// again. On the ultrawide it tiles the channel, so push back never has a tiled window to move.
@MainActor
final class Tiler {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes what tiling did and why an action did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "tiling")
    // order is the tiling order of the tiled windows, main window first.
    private var order: [WindowID] = []
    // assigned maps each tiled window to the frame it was last given and when.
    private var assigned: [WindowID: (frame: Frame, at: Double)] = [:]
    // floated holds the windows the owner moved out of the layout.
    private var floated: Set<WindowID> = []
    // released is when the primary mouse button last came up.
    private var released = 0.0

    // init builds a tiler for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // anchors is the layout the tiler reads.
    private var anchors: Anchors { app.anchors }

    // mouseUp records a mouse up, so a tiled window found off its frame after it was moved by hand.
    func mouseUp() {
        released = AppDelegate.now
    }

    // tileable reports whether w joins the layout: not anchored, fullscreen, a file panel, stashed or
    // cast off.
    private func tileable(_ w: WindowInfo) -> Bool {
        !w.isFilePanel && !w.isFullScreen && !anchors.pinned(w) && !anchors.stashed.contains(w.id)
            && !anchors.isCastOff(w.id)
    }

    // pass lays out list, the windows on screen front-most first, after a moor pass. Each window gets
    // a frame only when its frame in the layout changed, so an app that keeps its own size is left
    // alone, and a window found off its frame after a mouse up floats. It does nothing while tiling
    // is off, while paused, or while the mouse button is down.
    func pass(_ list: [WindowInfo], screens: Screens, mouseHeld: Bool) {
        let tiling = anchors.choices.tiling
        guard tiling.mode != .off, !anchors.choices.paused, !mouseHeld else { return }
        let now = AppDelegate.now
        let free = list.filter(tileable)
        floated.formIntersection(free.map(\.id))
        order = Tiling.order(order, free.map(\.id).filter { !floated.contains($0) })
        assigned = assigned.filter { id, _ in order.contains(id) }
        let byID = Dictionary(free.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in screens.full.indices {
            let ids = order.filter { byID[$0].flatMap { screens.index($0.frame) } == i }
            let frames = Tiling.layout(tiling.mode, app.organizer.area(screens, i), ids.count, ratio: tiling.ratio,
                                       gap: anchors.choices.gapPx)
            for (id, target) in zip(ids, frames) {
                guard let w = byID[id] else { continue }
                if let a = assigned[id], Actions.near(a.frame, target, tolerance: Actions.tolerance) {
                    if released > a.at, !Actions.near(w.frame, a.frame, tolerance: Actions.tolerance) {
                        floated.insert(id)
                        order.removeAll { $0 == id }
                        assigned[id] = nil
                        logger.notice("window \(id) moved by hand: floating until a mode is chosen again")
                    }
                    continue
                }
                if !Actions.near(w.frame, target, tolerance: Actions.tolerance) {
                    anchors.save(w)
                    app.windows.move(id, to: target)
                }
                assigned[id] = (target, now)
            }
        }
    }

    // run applies tiling action name and reports whether it did anything. Choosing a mode, even the
    // one in use, brings floated windows back into the layout.
    func run(_ name: String) -> Bool {
        if let mode = Tiling.mode(name) {
            choose(mode)
            return true
        }
        switch name {
        case Tiling.cycleName:
            choose(Tiling.next(anchors.choices.tiling.mode))
            return true
        case "grow-main", "shrink-main":
            let was = anchors.choices.tiling.ratio
            anchors.choices.tiling.ratio = Tiling.resized(was, grow: name == "grow-main")
            guard anchors.choices.tiling.ratio != was else { return false }
            app.save()
            return true
        default:
            guard let dir = Tiling.direction(name) else { return false }
            return Tiling.focusNames.contains(name) ? focus(dir) : swap(dir)
        }
    }

    // choose sets mode, forgets the floated windows and every frame given, and lays out again.
    private func choose(_ mode: TileMode) {
        anchors.choices.tiling.mode = mode
        floated = []
        assigned = [:]
        app.save()
        app.notify("Tiling", mode == .off ? "Off. Windows stay where they are." : "\(Keymaps.label(Tiling.modePrefix + mode.rawValue)).")
    }

    // neighbor returns the focused window and its nearest neighbor in dir among the windows on
    // screen, leaving out anchored windows when anchored is false.
    private func neighbor(_ dir: TileDirection, anchored: Bool) -> (WindowInfo, WindowInfo)? {
        let scan = app.windows.scan(Screens.current())
        guard let me = scan.focused else {
            logger.notice("no focused window")
            return nil
        }
        let pool = scan.windows.filter { !$0.isFilePanel && !$0.isFullScreen && (anchored || !anchors.pinned($0)) }
        guard let i = pool.firstIndex(where: { $0.id == me.id }),
              let k = Tiling.toward(dir, from: i, frames: pool.map(\.frame))
        else {
            logger.notice("no window \(dir.rawValue, privacy: .public) of the focused one")
            return nil
        }
        return (me, pool[k])
    }

    // focus brings the nearest window in dir to the front.
    private func focus(_ dir: TileDirection) -> Bool {
        guard let (_, other) = neighbor(dir, anchored: true) else { return false }
        app.windows.raise(other.id)
        return true
    }

    // swap trades the focused window's place with its nearest neighbor in dir: their places in the
    // layout while both are tiled, their frames otherwise. Anchored windows never swap.
    private func swap(_ dir: TileDirection) -> Bool {
        guard let (me, other) = neighbor(dir, anchored: false) else { return false }
        if anchors.choices.tiling.mode != .off, order.contains(me.id), order.contains(other.id) {
            order = Tiling.swapped(order, me.id, other.id)
            assigned[me.id] = nil
            assigned[other.id] = nil
            app.moor()
            return true
        }
        anchors.save(me)
        anchors.save(other)
        app.windows.move(me.id, to: other.frame)
        app.windows.move(other.id, to: me.frame)
        app.wake()
        return true
    }
}
