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

    // init builds a set of choices.
    public init(slots: [SlotKey: String] = [:], widths: Widths? = nil, heights: Heights? = nil, paused: Bool = false) {
        self.slots = slots
        self.widths = widths
        self.heights = heights
        self.paused = paused
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case slots, widths, heights, paused
    }

    // init decodes saved choices, skipping unknown slots and keeping what else is readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
        slots = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SlotKey(rawValue: k).map { ($0, v) } })
        widths = try? c.decodeIfPresent(Widths.self, forKey: .widths)
        heights = try? c.decodeIfPresent(Heights.self, forKey: .heights)
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
    }

    // encode writes the choices with slots keyed by slot name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }), forKey: .slots)
        try c.encodeIfPresent(widths, forKey: .widths)
        try c.encodeIfPresent(heights, forKey: .heights)
        try c.encode(paused, forKey: .paused)
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

    // init builds a window description.
    public init(id: WindowID, bundle: String, frame: Frame, onUltrawide: Bool, isMain: Bool,
                isFilePanel: Bool = false, isFullScreen: Bool = false) {
        self.id = id
        self.bundle = bundle
        self.frame = frame
        self.onUltrawide = onUltrawide
        self.isMain = isMain
        self.isFilePanel = isFilePanel
        self.isFullScreen = isFullScreen
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

// Move is one window frame change a pass asks for.
public struct Move: Equatable, Sendable {
    // id is the window to move.
    public var id: WindowID
    // frame is where it goes.
    public var frame: Frame
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

    // remoorNow forgets the windows on hold, so the next pass places everything again.
    public func remoorNow() {
        bursts = [:]
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

    // inUse returns the strip widths in use: the chosen widths, with 0 for an empty side.
    public func inUse() -> Widths {
        let w = widths
        let empty = emptySides()
        return Widths(left: empty.contains(.left) ? 0 : w.left, right: empty.contains(.right) ? 0 : w.right)
    }

    // channel returns the channel on screen, the ultrawide's usable frame.
    public func channel(_ screen: Frame) -> Frame {
        let w = inUse()
        return Geometry.regions(screen, w.left, w.right).channel
    }

    // slotFrame returns where the slot key sits on screen at its side's width, the chosen width when
    // the side is empty.
    public func slotFrame(_ screen: Frame, _ key: SlotKey) -> Frame {
        let use = inUse()
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
    func place(_ w: WindowInfo, _ frame: Frame) -> Move? {
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
        return Move(id: w.id, frame: frame)
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

    // moor returns the moves that put every pin in its slot and every free window on the ultrawide
    // in the channel. Nothing moves while paused, while the mouse button is down, or without an
    // ultrawide.
    public func moor(_ scene: Scene) -> [Move] {
        guard !choices.paused, !scene.mouseHeld, let screen = scene.screen else { return [] }
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
        let use = inUse()
        let h = heights
        let ch = Geometry.regions(screen, use.left, use.right).channel
        var moves: [Move] = []
        var seen: Set<WindowID> = []
        for w in scene.windows {
            seen.insert(w.id)
            if w.isFullScreen {
                continue
            }
            if let pin = pin(w.bundle, in: pins) {
                guard pinsWindow(pin, w) else { continue }
                castOff.remove(w.id)
                clamped[w.id] = nil
                let side = pin.slot.side
                let row = rows[pin.bundle] ?? nil
                let target = Geometry.slot(screen, side, row, side == .left ? use.left : use.right, topPct: h[side])
                if let move = place(w, target) {
                    moves.append(move)
                }
            } else if w.onUltrawide {
                if castOff.contains(w.id) {
                    // A cast-off window loses its clamped width, so it never grows back to it later.
                    clamped[w.id] = nil
                } else if let move = settle(w, ch) {
                    moves.append(move)
                }
            }
        }
        clamped = clamped.filter { seen.contains($0.key) }
        bursts = bursts.filter { seen.contains($0.key) }
        holders = holders.filter { seen.contains($0.value) }
        return moves
    }

    // pin returns the pin in pins for bundle, or nil.
    private func pin(_ bundle: String, in pins: [Pin]) -> Pin? {
        pins.first { $0.bundle == bundle }
    }
}
