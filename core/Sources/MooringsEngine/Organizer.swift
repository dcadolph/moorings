import MooringsCore

// Organizer lays out several free windows at once: it tiles and cascades them, cycles the windows
// of a stack or a slot, mirrors them, tidies the channel and undoes what it moved.
public final class Organizer {
    // tidyCounts lists how many front windows the Tidy entries line up.
    public static let tidyCounts = [2, 3]

    // wake marks windows as changing, so passes run until they settle.
    public var wake: () -> Void = {}
    // moor runs a pass now.
    public var moor: () -> Void = {}

    // platform reads and moves the windows.
    private let platform: Platform
    // anchors is the layout the organizer reads and changes.
    private let anchors: Anchors

    // init builds an organizer on platform and anchors.
    public init(platform: Platform, anchors: Anchors) {
        self.platform = platform
        self.anchors = anchors
    }

    // area returns the frame organize actions work in on screen i: the channel on the ultrawide and
    // the usable frame elsewhere.
    public func area(_ screens: Screens, _ i: Int) -> Frame {
        i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
    }

    // place moves each window to the frame at the same index, saving where each was first so Undo
    // and Restore can put it back.
    private func place(_ list: [WindowInfo], _ frames: [Frame]) -> Bool {
        for (w, f) in zip(list, frames) {
            anchors.save(w)
            platform.windows.move(w.id, to: f, from: nil, behavior: anchors.choices.behavior)
        }
        wake()
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

    // run applies organize action name on the screen of the window with id window, or of the focused
    // window when window is nil or gone, and reports whether anything changed. A tray menu passes the
    // window that was in front before the menu took the focus.
    @discardableResult
    public func run(_ name: String, window: WindowID? = nil) -> Bool {
        guard !anchors.choices.paused else { return false }
        let screens = platform.screens.current()
        let scan = platform.windows.scan(screens, full: true)
        let chosen = window.flatMap { id in scan.windows.first { $0.id == id } } ?? scan.focused
        guard let win = chosen, let i = screens.index(win.frame) else { return false }
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
            guard let me = list.firstIndex(where: { $0.id == win.id }) else { return false }
            let stack = Tile.stack(anchorOf: me, among: list.map(\.frame), choices: anchors.choices.stacking)
                .map { list[$0] }.sorted { $0.id < $1.id }
            guard stack.count > 1, let at = stack.firstIndex(where: { $0.id == win.id }) else { return false }
            let dir = name == "cycle-stacked-windows" ? 1 : -1
            platform.windows.raise(stack[((at + dir) % stack.count + stack.count) % stack.count].id)
            return true
        case "cycle-slot-windows", "cycle-slot-windows-backward":
            guard let next = anchors.nextSlotWindow(after: win.id, backward: name == "cycle-slot-windows-backward")
            else { return false }
            platform.windows.raise(next)
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
    public func tidy(_ n: Int) {
        guard !anchors.choices.paused else { return }
        let screens = platform.screens.current()
        let scan = platform.windows.scan(screens, full: true)
        guard let i = screens.ultrawide ?? scan.focused.flatMap({ screens.index($0.frame) }) else { return }
        let list = organizable(scan.windows, screens, i)
        let pairs = Tile.tidy(area(screens, i), list.map { TileWindow(id: $0.id, frame: $0.frame) }, n,
                              gap: anchors.choices.gapPx)
        let byID = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        _ = place(pairs.compactMap { byID[$0.0.id] }, pairs.map(\.1))
        moor()
    }

    // undo puts every window a fill, tidy or window action moved back where it was before the first
    // move.
    public func undo() {
        guard !anchors.choices.paused else { return }
        _ = platform.windows.scan(platform.screens.current(), full: true)
        for (id, f) in anchors.undo() {
            platform.windows.move(id, to: f, from: nil, behavior: anchors.choices.behavior)
        }
        platform.notifier.notify("Tidy undone", "Every window is back where it was before it was tidied or moved.")
        wake()
    }
}
