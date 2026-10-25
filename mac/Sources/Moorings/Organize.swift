import AppKit
import os

import MooringsCore

// Organizer lays out several free windows at once, tidies the channel, and saves and recalls
// workspaces.
@MainActor
final class Organizer {
    // tidyCounts lists how many front windows the Tidy entries line up.
    static let tidyCounts = [2, 3]

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes what an organize action or a workspace could not do.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "organize")
    // setup is the signature of the displays last seen, so a display change recalls its workspace
    // once. The displays attached at launch count as handled.
    private var setup: String

    // init builds an organizer for app.
    init(app: AppDelegate) {
        self.app = app
        setup = Workspaces.signature(Screens.current().full)
    }

    // anchors is the layout the organizer reads and changes.
    private var anchors: Anchors { app.anchors }

    // area returns the frame organize actions work in on screen i: the channel on the ultrawide and
    // the usable frame elsewhere.
    private func area(_ screens: Screens, _ i: Int) -> Frame {
        i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
    }

    // place moves each window to the frame at the same index, saving where each was first so Undo
    // and Restore can put it back.
    private func place(_ list: [WindowInfo], _ frames: [Frame]) -> Bool {
        for (w, f) in zip(list, frames) {
            anchors.save(w)
            app.windows.move(w.id, to: f)
        }
        app.wake()
        return !list.isEmpty
    }

    // organizable returns the windows on screen i that organize actions may move: not pinned and not
    // fullscreen, front-most first.
    private func organizable(_ windows: [WindowInfo], _ screens: Screens, _ i: Int) -> [WindowInfo] {
        windows.filter { !anchors.pinned($0) && !$0.isFullScreen && screens.index($0.frame) == i }
    }

    // sorted returns list ordered by order on the tile inputs.
    private func sorted(_ list: [WindowInfo], _ order: (TileWindow, TileWindow) -> Bool) -> [WindowInfo] {
        list.sorted { order(TileWindow(id: $0.id, frame: $0.frame), TileWindow(id: $1.id, frame: $1.frame)) }
    }

    // run applies organize action name on the focused window's screen and reports whether anything
    // changed.
    @discardableResult
    func run(_ name: String) -> Bool {
        guard !anchors.choices.paused else { return false }
        let screens = Screens.current()
        let scan = app.windows.scan(screens)
        guard let win = scan.focused, let i = screens.index(win.frame) else { return false }
        let a = area(screens, i)
        let gap = anchors.choices.gapPx
        let list = organizable(scan.windows, screens, i)
        switch name {
        case "tile-columns":
            let l = sorted(list, Tile.byX)
            return place(l, Tile.columns(a, l.count, gap: gap))
        case "tile-rows":
            let l = sorted(list, Tile.byY)
            return place(l, Tile.rows(a, l.count, gap: gap))
        case "tile-all":
            let l = sorted(list, Tile.byY)
            return place(l, Tile.grid(a, l.count, gap: gap))
        case "tile-active-app":
            let l = sorted(list.filter { $0.bundle == win.bundle }, Tile.byY)
            return place(l, Tile.grid(a, l.count, gap: gap))
        case "cascade-all":
            return cascade(list, a)
        case "cascade-active-app":
            return cascade(list.filter { $0.bundle == win.bundle }, a)
        case "cycle-stacked-windows", "cycle-stacked-windows-backward":
            let stack = list.filter { Actions.near($0.frame, win.frame) }.sorted { $0.id < $1.id }
            guard let at = stack.firstIndex(where: { $0.id == win.id }) else { return false }
            let dir = name == "cycle-stacked-windows" ? 1 : -1
            app.windows.raise(stack[((at + dir) % stack.count + stack.count) % stack.count].id)
            return true
        case "reverse-all":
            return place(list, list.map { Tile.reverse(a, $0.frame) })
        default:
            return false
        }
    }

    // cascade cascades list in area, back-most window first so the front-most stays on top.
    private func cascade(_ list: [WindowInfo], _ area: Frame) -> Bool {
        let back = Array(list.reversed())
        return place(back, Tile.cascade(area, back.map(\.frame), step: Tile.cascadeStep))
    }

    // tidy lines up the n front-most free windows in equal columns, left to right in their current
    // order, in the channel while the ultrawide is attached and on the focused window's screen
    // otherwise.
    func tidy(_ n: Int) {
        guard !anchors.choices.paused else { return }
        let screens = Screens.current()
        let scan = app.windows.scan(screens)
        guard let i = screens.ultrawide ?? scan.focused.flatMap({ screens.index($0.frame) }) else { return }
        let list = organizable(scan.windows, screens, i)
        let pairs = Tile.tidy(area(screens, i), list.map { TileWindow(id: $0.id, frame: $0.frame) }, n,
                              gap: anchors.choices.gapPx)
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        _ = place(pairs.compactMap { byID[$0.0.id] }, pairs.map(\.1))
        app.moor()
    }

    // undo puts every window a fill, tidy or window action moved back where it was before the first
    // move.
    func undo() {
        guard !anchors.choices.paused else { return }
        _ = app.windows.scan(Screens.current())
        for (id, f) in anchors.undo() {
            app.windows.move(id, to: f)
        }
        app.notify("Tidy undone", "Every window is back where it was before it was tidied or moved.")
        app.wake()
    }

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

    // recall puts back the workspace saved as name and reports whether it existed. Windows whose app
    // is not running, or whose display is gone, stay where they are.
    @discardableResult
    func recall(_ name: String) -> Bool {
        guard !anchors.choices.paused else { return false }
        guard let ws = anchors.choices.workspaces[name] else {
            logger.notice("no workspace is named \(name, privacy: .public)")
            return false
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
        let areas = screens.full.indices.map { ScreenAreas(full: screens.full[$0], area: area(screens, $0)) }
        let matched = Workspaces.match(ws.windows, info)
        var missed = 0
        for (i, saved) in ws.windows.enumerated() {
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
        app.notify("Workspace \(name)", missed > 0 ? "Recalled. \(missed) windows had no running app or display."
            : "Recalled.")
        app.save()
        return true
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

    // screensChanged recalls the workspace tied to the display setup just plugged in.
    func screensChanged() {
        let now = Workspaces.signature(Screens.current().full)
        guard now != setup else { return }
        setup = now
        if let name = anchors.choices.workspaces.keys.sorted().first(where: { anchors.choices.workspaces[$0]?.setup == now }) {
            recall(name)
        }
    }

    // saveProfile saves the current shortcuts, snapping, behavior, menu, rules and theme as the profile
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

    // applyProfile switches to the profile saved as name: its settings take effect, hotkeys and the
    // theme follow, and its workspaces are recalled in order. Anchored apps and strip sizes stay.
    @discardableResult
    func applyProfile(_ name: String) -> Bool {
        guard let profile = anchors.choices.profiles.first(where: { $0.name == name }) else {
            logger.notice("no profile is named \(name, privacy: .public)")
            return false
        }
        anchors.choices = anchors.choices.applying(profile)
        app.save()
        for ws in profile.workspaces {
            recall(ws)
        }
        app.notify("Profile \(name)", profile.workspaces.isEmpty ? "Switched." :
            "Switched and recalled \(profile.workspaces.joined(separator: ", ")).")
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
