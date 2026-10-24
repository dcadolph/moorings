import Foundation

// WindowID is a window's CGWindowID, stable for the life of the window.
public typealias WindowID = UInt32

// SlotKey names one of the four slots, two per strip.
public enum SlotKey: String, CaseIterable, Codable, Sendable {
    case leftTop = "left-top"
    case leftBottom = "left-bottom"
    case rightTop = "right-top"
    case rightBottom = "right-bottom"

    // side is the strip the slot sits in.
    public var side: Side { self == .leftTop || self == .leftBottom ? .left : .right }

    // row is the slot's row within its strip.
    public var row: Row { self == .leftTop || self == .rightTop ? .top : .bottom }

    // title is the slot's menu label.
    public var title: String {
        switch self {
        case .leftTop: "Left top"
        case .leftBottom: "Left bottom"
        case .rightTop: "Right top"
        case .rightBottom: "Right bottom"
        }
    }
}

// Pin is one anchored app and the slot it was chosen for.
public struct Pin: Equatable, Sendable {
    // bundle is the app's bundle ID.
    public var bundle: String
    // slot is the slot the app was put in.
    public var slot: SlotKey

    // init builds a pin.
    public init(bundle: String, slot: SlotKey) {
        self.bundle = bundle
        self.slot = slot
    }
}

// Choices holds what the owner picked and moorings saves: the slots, the widths, the heights, and
// whether the anchor is weighed. Cast off is never part of it.
public struct Choices: Equatable, Sendable, Codable {
    // slots maps each chosen slot to a bundle ID. A missing slot is empty.
    public var slots: [SlotKey: String]
    // widths is the chosen strip widths, nil until one is chosen.
    public var widths: Widths?
    // heights is the chosen top row heights, nil until one is chosen.
    public var heights: Heights?
    // paused reports whether the anchor is weighed, so nothing is held.
    public var paused: Bool
    // fullscreenFills reports whether native fullscreen on a free window is turned into a channel fill.
    public var fullscreenFills: Bool
    // pinFullscreenFills reports whether native fullscreen on a pinned window is sent back to its slot.
    public var pinFullscreenFills: Bool
    // keymap names the built-in shortcut set.
    public var keymap: String = Keymap.rectangle.rawValue
    // shortcuts maps an action to the shortcut chosen for it, nil to turn its shortcut off.
    public var shortcuts: [String: StoredShortcut?] = [:]
    // sizes lists the custom sizes, each with an optional shortcut.
    public var sizes: [StoredSize] = []
    // gapPx is the gap in points window actions leave around a window.
    public var gapPx: Double = 0
    // ignores lists the apps whose windows the shortcuts leave alone while they are in front.
    public var ignores: [String] = []
    // snap reports whether dragging a window to an edge snaps it.
    public var snap: Bool = true
    // theme names the color theme for the footprint, banners and settings.
    public var theme: ThemeName = .harborDark
    // workspaces holds the saved workspaces by name.
    public var workspaces: [String: Workspace] = [:]
    // checkUpdates reports whether moorings looks for a new release once a day.
    public var checkUpdates: Bool = true
    // mouseButtons maps an extra mouse button, numbered from 2, to the action it runs.
    public var mouseButtons: [String: String] = [:]

    // init builds a set of choices.
    public init(slots: [SlotKey: String] = [:], widths: Widths? = nil, heights: Heights? = nil, paused: Bool = false,
                fullscreenFills: Bool = true, pinFullscreenFills: Bool = true) {
        self.slots = slots
        self.widths = widths
        self.heights = heights
        self.paused = paused
        self.fullscreenFills = fullscreenFills
        self.pinFullscreenFills = pinFullscreenFills
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case slots, widths, heights, paused, fullscreenFills, pinFullscreenFills, keymap, shortcuts, sizes, gapPx
        case ignores, snap, theme, workspaces, checkUpdates, mouseButtons
    }

    // init decodes saved choices, skipping unknown slots and keeping what else is readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
        slots = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SlotKey(rawValue: k).map { ($0, v) } })
        widths = try? c.decodeIfPresent(Widths.self, forKey: .widths)
        heights = try? c.decodeIfPresent(Heights.self, forKey: .heights)
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
        fullscreenFills = (try? c.decodeIfPresent(Bool.self, forKey: .fullscreenFills)) ?? true
        pinFullscreenFills = (try? c.decodeIfPresent(Bool.self, forKey: .pinFullscreenFills)) ?? true
        keymap = (try? c.decodeIfPresent(String.self, forKey: .keymap)) ?? Keymap.rectangle.rawValue
        shortcuts = (try? c.decodeIfPresent([String: StoredShortcut?].self, forKey: .shortcuts)) ?? [:]
        sizes = (try? c.decodeIfPresent([StoredSize].self, forKey: .sizes)) ?? []
        gapPx = (try? c.decodeIfPresent(Double.self, forKey: .gapPx)) ?? 0
        ignores = (try? c.decodeIfPresent([String].self, forKey: .ignores)) ?? []
        snap = (try? c.decodeIfPresent(Bool.self, forKey: .snap)) ?? true
        theme = (try? c.decodeIfPresent(ThemeName.self, forKey: .theme)) ?? .harborDark
        workspaces = (try? c.decodeIfPresent([String: Workspace].self, forKey: .workspaces)) ?? [:]
        checkUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checkUpdates)) ?? true
        mouseButtons = (try? c.decodeIfPresent([String: String].self, forKey: .mouseButtons)) ?? [:]
    }

    // encode writes the choices with slots keyed by slot name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }), forKey: .slots)
        try c.encodeIfPresent(widths, forKey: .widths)
        try c.encodeIfPresent(heights, forKey: .heights)
        try c.encode(paused, forKey: .paused)
        try c.encode(fullscreenFills, forKey: .fullscreenFills)
        try c.encode(pinFullscreenFills, forKey: .pinFullscreenFills)
        try c.encode(keymap, forKey: .keymap)
        try c.encode(shortcuts, forKey: .shortcuts)
        try c.encode(sizes, forKey: .sizes)
        try c.encode(gapPx, forKey: .gapPx)
        try c.encode(ignores, forKey: .ignores)
        try c.encode(snap, forKey: .snap)
        try c.encode(theme, forKey: .theme)
        try c.encode(workspaces, forKey: .workspaces)
        try c.encode(checkUpdates, forKey: .checkUpdates)
        try c.encode(mouseButtons, forKey: .mouseButtons)
    }

    // encode returns choices as sorted JSON for saving.
    public static func encode(_ choices: Choices) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(choices)
    }

    // decode returns saved choices, or the defaults when data is not readable.
    public static func decode(_ data: Data) -> Choices {
        (try? JSONDecoder().decode(Choices.self, from: data)) ?? Choices()
    }
}

// WindowInfo is what one pass knows about a movable window.
public struct WindowInfo: Equatable, Sendable {
    // id is the window's id.
    public var id: WindowID
    // bundle is the bundle ID of the window's app.
    public var bundle: String
    // frame is the window's frame in global top-left coordinates.
    public var frame: Frame
    // onUltrawide reports whether the window is on the ultrawide.
    public var onUltrawide: Bool
    // isMain reports whether the window is its app's main window.
    public var isMain: Bool
    // isFilePanel reports whether the window is an open or save panel.
    public var isFilePanel: Bool
    // isFullScreen reports whether the window is in native fullscreen.
    public var isFullScreen: Bool
    // zoomRect is the window's green button rect, nil when the window did not report one.
    public var zoomRect: Frame?

    // init builds a window description.
    public init(id: WindowID, bundle: String, frame: Frame, onUltrawide: Bool, isMain: Bool,
                isFilePanel: Bool = false, isFullScreen: Bool = false, zoomRect: Frame? = nil) {
        self.id = id
        self.bundle = bundle
        self.frame = frame
        self.onUltrawide = onUltrawide
        self.isMain = isMain
        self.isFilePanel = isFilePanel
        self.isFullScreen = isFullScreen
        self.zoomRect = zoomRect
    }
}

// Scene is what one pass sees.
public struct Scene: Sendable {
    // screen is the ultrawide's usable frame, nil when none is attached.
    public var screen: Frame?
    // windows lists the movable windows on every screen, front-most first.
    public var windows: [WindowInfo]
    // focused is the focused window's id, nil when none.
    public var focused: WindowID?
    // mouseHeld reports whether the primary mouse button is down.
    public var mouseHeld: Bool
    // now is the time of the pass in seconds.
    public var now: Double

    // init builds a scene.
    public init(screen: Frame?, windows: [WindowInfo], focused: WindowID? = nil, mouseHeld: Bool = false, now: Double) {
        self.screen = screen
        self.windows = windows
        self.focused = focused
        self.mouseHeld = mouseHeld
        self.now = now
    }
}

// Edges names the edges a move keeps in place when a window will not shrink to fit.
public struct Edges: Equatable, Sendable {
    // right keeps the right edge instead of the left.
    public var right = false
    // bottom keeps the bottom edge instead of the top.
    public var bottom = false

    // init builds a set of edges.
    public init(right: Bool = false, bottom: Bool = false) {
        self.right = right
        self.bottom = bottom
    }
}

// Move is one window change a pass asks for.
public struct Move: Equatable, Sendable {
    // id is the window to move.
    public var id: WindowID
    // frame is where it goes, grown to any size the window is known to keep.
    public var frame: Frame
    // target is the frame the layout wants before any known minimum size is applied.
    public var target: Frame
    // anchor is the edges kept in place when the window will not shrink.
    public var anchor: Edges
    // exitFullScreen asks for the window to leave native fullscreen instead of a frame change.
    public var exitFullScreen: Bool

    // init builds a move.
    public init(id: WindowID, frame: Frame, target: Frame? = nil, anchor: Edges = Edges(), exitFullScreen: Bool = false) {
        self.id = id
        self.frame = frame
        self.target = target ?? frame
        self.anchor = anchor
        self.exitFullScreen = exitFullScreen
    }
}

// Anchors holds the chosen layout and decides where each window belongs: pins in their slots on
// the ultrawide and free windows in the channel between the strips.
public final class Anchors {
    // tolerance is how many points a frame may drift before it is corrected.
    public static let tolerance = 2.0
    // burstMoves moves of one window inside burstSeconds put it on hold for holdSeconds.
    static let burstMoves = 4
    // burstSeconds is the window in which moves count toward a hold.
    static let burstSeconds = 10.0
    // holdSeconds is how long a window that fights its place is left alone.
    static let holdSeconds = 60.0
    // openSeconds is how long an anchored app being opened keeps its strip before its window shows.
    static let openSeconds = 30.0

    // Clamp records a window the channel narrowed: its own width and the width it was given.
    struct Clamp {
        // natural is the window's width before the clamp.
        var natural: Double
        // set is the width the clamp gave it.
        var set: Double
    }

    // Burst counts recent moves of one window to the same target.
    struct Burst {
        // target is the frame the moves aimed at.
        var target: Frame
        // moves is how many moves were made since since.
        var moves: Int
        // since is when the count started.
        var since: Double
        // holdUntil is when a hold ends, nil when none.
        var holdUntil: Double?
    }

    // choices is what the owner picked. The app saves it after each change.
    public var choices: Choices
    // clamped records the windows the channel narrowed.
    var clamped: [WindowID: Clamp] = [:]
    // castOff holds the windows let free over the strips.
    var castOff: Set<WindowID> = []
    // bursts counts recent moves per window.
    var bursts: [WindowID: Burst] = [:]
    // holders maps each pinned bundle to the window its pin holds.
    var holders: [String: WindowID] = [:]
    // openedAt maps an app moorings opened to when, so it keeps its strip while it opens.
    var openedAt: [String: Double] = [:]
    // present holds the bundles whose pinned window showed in the last pass, nil before one.
    var present: Set<String>?
    // now is the time of the last pass.
    var now = 0.0
    // lifted holds the pins lifted over their strip and the channel.
    var lifted: Set<WindowID> = []
    // released holds the pins let go after the owner moved them by hand.
    var released: Set<WindowID> = []
    // placed records where each pin was last put and when.
    var placed: [WindowID: PinPlacement] = [:]
    // zoom holds each window's green button rect as of the last pass.
    var zoom: [WindowID: ZoomSpot] = [:]
    // filled records where a free window's green button click filled the channel, and from where.
    var filled: [WindowID: ZoomFill] = [:]
    // saved records each window's frame before moorings first moved it with an action.
    var saved: [WindowID: Frame] = [:]
    // floors records the smallest size each window was seen to keep.
    var floors: [WindowID: Floor] = [:]
    // pendingFill records when each window was asked to leave native fullscreen.
    var pendingFill: [WindowID: Double] = [:]
    // minPoints is the widest floor among the pins on each side.
    var minPoints: [Side: Double] = [:]
    // minBy names the bundle whose floor sets minPoints on each side.
    public internal(set) var minBy: [Side: String] = [:]
    // justReleased lists the pins the last pass let go, for the app to tell the owner.
    public internal(set) var justReleased: [WindowID] = []

    // init builds Anchors from saved choices.
    public init(choices: Choices = Choices()) {
        self.choices = choices
    }

    // widths returns the strip widths in effect.
    public var widths: Widths { Layout.widths(saved: choices.widths, config: nil).0 }

    // heights returns the top row heights in effect.
    public var heights: Heights {
        let saved = PartialHeights(left: choices.heights?.left, right: choices.heights?.right)
        return Layout.heights(saved: saved, config: PartialHeights()).0
    }

    // setWidths saves a width pair, ignoring one that leaves no channel.
    public func setWidths(_ w: Widths) {
        if Layout.validSplit(w) {
            choices.widths = w
        }
    }

    // setTop saves side's top row height, ignoring one that leaves a row under the minimum.
    public func setTop(_ side: Side, _ pct: Double) {
        guard Layout.validTop(pct) else { return }
        var h = heights
        h[side] = pct
        choices.heights = h
    }

    // assignments returns the bundle in each slot, "" for an empty one.
    public func assignments() -> [SlotKey: String] {
        Dictionary(uniqueKeysWithValues: SlotKey.allCases.map { ($0, choices.slots[$0] ?? "") })
    }

    // pins returns the anchored apps in slot order. A bundle in two slots keeps the first.
    public func pins() -> [Pin] {
        var seen: Set<String> = []
        var out: [Pin] = []
        for key in SlotKey.allCases {
            let bundle = choices.slots[key] ?? ""
            if bundle != "" && seen.insert(bundle).inserted {
                out.append(Pin(bundle: bundle, slot: key))
            }
        }
        return out
    }

    // assign puts bundle in the slot key. An app already in another slot moves, and "" empties the
    // slot.
    public func assign(_ key: SlotKey, _ bundle: String) {
        for (k, v) in choices.slots where v == bundle {
            choices.slots[k] = ""
        }
        choices.slots[key] = bundle
    }

    // clearSlots empties every slot.
    public func clearSlots() {
        choices.slots = Dictionary(uniqueKeysWithValues: SlotKey.allCases.map { ($0, "") })
    }

    // lock puts bundle in the slot key and marks it opening, so it keeps its strip while the app
    // opens its window.
    public func lock(_ key: SlotKey, _ bundle: String, now: Double) {
        if bundle != "" {
            openedAt[bundle] = now
        }
        assign(key, bundle)
    }

    // launch marks every anchored app opening, so each keeps its strip through the first pass.
    public func launch(now: Double) {
        for pin in pins() {
            openedAt[pin.bundle] = now
        }
    }

    // opening returns the anchored apps still waiting for a window, in slot order.
    public func opening() -> [String] {
        pins().map(\.bundle).filter { openedAt[$0] != nil }
    }

    // remoorNow forgets the windows on hold, the learned sizes, the releases and the lifts, so the
    // next pass places everything again.
    public func remoorNow() {
        bursts = [:]
        floors = [:]
        placed = [:]
        released = []
        lifted = []
    }

    // holdsSpace reports whether bundle's pin keeps its strip: its window showed, no pass ran yet,
    // or moorings opened it moments ago.
    func holdsSpace(_ bundle: String) -> Bool {
        if present?.contains(bundle) ?? true {
            return true
        }
        guard let started = openedAt[bundle] else { return false }
        return now - started <= Self.openSeconds
    }

    // emptySides returns the sides with no anchored app keeping its strip, which the channel takes.
    public func emptySides() -> [Side] {
        let held = Set(pins().filter { holdsSpace($0.bundle) }.map(\.slot.side))
        return [Side.left, .right].filter { !held.contains($0) }
    }

    // inUse returns the strip widths in use: the chosen widths, with 0 for an empty side. On screen,
    // each held side grows to fit the widest pin there that will not shrink, while the channel keeps
    // at least Layout.minChannelPct.
    public func inUse(_ screen: Frame? = nil) -> Widths {
        let w = widths
        let empty = emptySides()
        let left = empty.contains(.left) ? 0 : w.left
        let right = empty.contains(.right) ? 0 : w.right
        guard let screen, screen.w > 0 else { return Widths(left: left, right: right) }
        let grow = { (side: Side, pct: Double) -> Double in
            pct > 0 ? max(0, ((self.minPoints[side] ?? 0) + 0.5) * 100 / screen.w - pct) : 0
        }
        var gl = grow(.left, left)
        var gr = grow(.right, right)
        let room = 100 - Layout.minChannelPct - left - right
        if gl + gr > room {
            let total = gl + gr
            gl = gl * room / total
            gr = gr * room / total
        }
        return Widths(left: left + gl, right: right + gr)
    }

    // channel returns the channel on screen, the ultrawide's usable frame.
    public func channel(_ screen: Frame) -> Frame {
        let w = inUse(screen)
        return Geometry.regions(screen, w.left, w.right).channel
    }

    // slotFrame returns where the slot key sits on screen at its side's width, the chosen width when
    // the side is empty.
    public func slotFrame(_ screen: Frame, _ key: SlotKey) -> Frame {
        let use = inUse(screen)
        let pct = key.side == .left ? (use.left > 0 ? use.left : widths.left) : (use.right > 0 ? use.right : widths.right)
        return Geometry.slot(screen, key.side, key.row, pct, topPct: heights[key.side])
    }

    // rows returns the row of each held pin, nil when the pin has its side to itself.
    func rows(_ held: [Pin]) -> [String: Row?] {
        var out: [String: Row?] = [:]
        for side in [Side.left, .right] {
            let list = held.filter { $0.slot.side == side }
            for pin in list {
                out[pin.bundle] = list.count == 1 ? nil : pin.slot.row
            }
        }
        return out
    }

    // pinsWindow reports whether pin holds w. A pin holds one window: the one it already holds, or
    // else the app's main window, which it then keeps. An open or save panel is never held.
    func pinsWindow(_ pin: Pin, _ w: WindowInfo) -> Bool {
        if let held = holders[pin.bundle] {
            return held == w.id
        }
        if w.isMain && !w.isFilePanel {
            holders[pin.bundle] = w.id
            return true
        }
        return false
    }

    // pin returns the pin for bundle, or nil when the app is not anchored.
    func pin(_ bundle: String) -> Pin? {
        pins().first { $0.bundle == bundle }
    }

    // pinned reports whether a pin holds w.
    public func pinned(_ w: WindowInfo) -> Bool {
        guard let pin = pin(w.bundle) else { return false }
        return pinsWindow(pin, w)
    }

    // hasCastOff reports whether any window is cast off.
    public var hasCastOff: Bool { !castOff.isEmpty }

    // isCastOff reports whether the window with id is cast off.
    public func isCastOff(_ id: WindowID) -> Bool {
        castOff.contains(id)
    }

    // castReason returns why w cannot be cast off, or nil when it can. ultrawide is the ultrawide's
    // usable frame, nil when none is attached.
    public func castReason(_ w: WindowInfo?, ultrawide: Frame?) -> String? {
        guard let w else { return "There is no focused window to cast off." }
        if ultrawide == nil || !w.onUltrawide {
            return "Only windows on the ultrawide are held in the channel."
        }
        if pinned(w) {
            return "Pinned windows stay in their slot."
        }
        return nil
    }

    // toggleCastOff lets free window w cover the strips, or puts it back under the channel rules,
    // and reports whether it changed.
    @discardableResult
    public func toggleCastOff(_ w: WindowInfo?, ultrawide: Frame?) -> Bool {
        if let w, castOff.remove(w.id) != nil {
            return true
        }
        guard let w, castReason(w, ultrawide: ultrawide) == nil else { return false }
        castOff.insert(w.id)
        return true
    }

    // prune forgets cast-off windows that no longer exist, so a later window with a reused id is
    // held in the channel.
    public func prune(alive: Set<WindowID>) {
        castOff.formIntersection(alive)
    }

    // place returns a move of w to frame unless it is already there. A window that keeps moving
    // away from the same frame is left alone for holdSeconds.
    func place(_ w: WindowInfo, _ target: Frame, _ anchor: Edges = Edges()) -> Move? {
        let frame = fit(w.id, target, anchor)
        var b = bursts[w.id]
        if let current = b, !Actions.near(current.target, frame, tolerance: Self.tolerance) {
            b = nil
        }
        if let until = b?.holdUntil, now < until {
            return nil
        }
        if Actions.near(w.frame, frame, tolerance: Self.tolerance) {
            return nil
        }
        var burst = b ?? Burst(target: frame, moves: 0, since: now)
        burst.holdUntil = nil
        if now - burst.since > Self.burstSeconds {
            burst.moves = 0
            burst.since = now
        }
        burst.moves += 1
        if burst.moves >= Self.burstMoves {
            burst.moves = 0
            burst.since = now
            burst.holdUntil = now + Self.holdSeconds
        }
        bursts[w.id] = burst
        return Move(id: w.id, frame: frame, target: target, anchor: anchor)
    }

    // settle keeps free window w inside channel ch, and lets a window the channel once narrowed grow
    // back toward its own width when the channel widens.
    func settle(_ w: WindowInfo, _ ch: Frame) -> Move? {
        var c = clamped[w.id]
        if let current = c, abs(w.frame.w - current.set) > Self.tolerance {
            c = nil
        }
        var f = w.frame
        if let c {
            f.w = c.natural
        }
        let want = Geometry.clamp(f, ch)
        clamped[w.id] = want.w < f.w ? Clamp(natural: f.w, set: want.w) : nil
        return place(w, want)
    }

    // moor returns the moves that put every pin in its slot, or over the channel while lifted, and
    // every free window on the ultrawide in the channel. A pin the owner moved by hand is released
    // and left alone. Native fullscreen is turned back into a slot or a channel fill when the
    // choices say so. Nothing moves while paused, while the mouse button is down, or without an
    // ultrawide.
    public func moor(_ scene: Scene) -> [Move] {
        justReleased = []
        if choices.paused {
            placed = [:]
            return []
        }
        guard !scene.mouseHeld, let screen = scene.screen else { return [] }
        now = scene.now
        let pins = pins()
        var shown: Set<String> = []
        for w in scene.windows {
            if let pin = pin(w.bundle, in: pins), pinsWindow(pin, w) {
                shown.insert(pin.bundle)
            }
        }
        present = shown
        for bundle in shown {
            openedAt[bundle] = nil
        }
        let rows = rows(pins.filter { holdsSpace($0.bundle) })
        measure(scene.windows, pins)
        let use = inUse(screen)
        let h = heights
        let ch = Geometry.regions(screen, use.left, use.right).channel
        var moves: [Move] = []
        var seen: Set<WindowID> = []
        for w in scene.windows {
            seen.insert(w.id)
            if let pin = pin(w.bundle, in: pins) {
                guard pinsWindow(pin, w) else { continue }
                if w.isFullScreen {
                    if choices.pinFullscreenFills, let exit = leaveFullScreen(w) {
                        moves.append(exit)
                    }
                    continue
                }
                pendingFill[w.id] = nil
                castOff.remove(w.id)
                clamped[w.id] = nil
                let side = pin.slot.side
                let row = rows[pin.bundle] ?? nil
                let pct = side == .left ? use.left : use.right
                let target = lifted.contains(w.id) ? Geometry.lift(screen, side, use.left, use.right)
                    : Geometry.slot(screen, side, row, pct, topPct: h[side])
                if let move = moorPin(w, target, Edges(right: side == .right, bottom: row == .bottom)) {
                    moves.append(move)
                }
            } else if w.onUltrawide {
                if w.isFullScreen {
                    if choices.fullscreenFills, let exit = leaveFullScreen(w) {
                        moves.append(exit)
                    }
                } else if let started = pendingFill[w.id] {
                    pendingFill[w.id] = nil
                    clamped[w.id] = nil
                    if let move = now - started <= Self.pendingSeconds ? place(w, ch) : settle(w, ch) {
                        moves.append(move)
                    }
                } else if castOff.contains(w.id) {
                    // A cast-off window loses its clamped width, so it never grows back to it later.
                    clamped[w.id] = nil
                    cacheZoom(w, w.frame, free: true)
                } else if let move = settle(w, ch) {
                    moves.append(move)
                } else {
                    cacheZoom(w, w.frame, free: true)
                }
            }
        }
        clamped = clamped.filter { seen.contains($0.key) }
        bursts = bursts.filter { seen.contains($0.key) }
        holders = holders.filter { seen.contains($0.value) }
        pendingFill = pendingFill.filter { seen.contains($0.key) }
        floors = floors.filter { seen.contains($0.key) }
        placed = placed.filter { seen.contains($0.key) }
        zoom = zoom.filter { seen.contains($0.key) }
        filled = filled.filter { seen.contains($0.key) }
        released.formIntersection(seen)
        lifted.formIntersection(seen)
        return moves
    }

    // pin returns the pin in pins for bundle, or nil.
    private func pin(_ bundle: String, in pins: [Pin]) -> Pin? {
        pins.first { $0.bundle == bundle }
    }
}
