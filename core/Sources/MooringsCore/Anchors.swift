import Foundation

// WindowID is a window's id: the CGWindowID on macOS and the HWND on Windows, stable for the life
// of the window.
public typealias WindowID = UInt64

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

// SlotPart is the share of a slot an action gave one of the slot's windows.
public struct SlotPart: Equatable, Sendable {
    // name is the action that chose the part.
    public var name: String
    // unit is the part in fractions of the slot: x and y from the slot's origin, w and h of its size.
    public var unit: Frame

    // init builds a part.
    public init(name: String, unit: Frame) {
        self.name = name
        self.unit = unit
    }

    // frame returns the part's frame inside area.
    public func frame(in area: Frame) -> Frame {
        Frame(x: area.x + unit.x * area.w, y: area.y + unit.y * area.h, w: unit.w * area.w, h: unit.h * area.h)
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
    // widthPresets lists the width pairs the owner saved as presets, in the order saved.
    public var widthPresets: [Widths] = []
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
    // workspaces holds the saved workspaces by name.
    public var workspaces: [String: Workspace] = [:]
    // checkUpdates reports whether moorings looks for a new release every few hours.
    public var checkUpdates: Bool = true
    // mouseButtons maps an extra mouse button, numbered from 2, to the action it runs.
    public var mouseButtons: [String: String] = [:]
    // buttonClicks maps a title bar button and modifier, such as red+option, to the action a click
    // runs instead of the button's own. Empty keeps every button as macOS and moorings ship it.
    public var buttonClicks: [String: String] = [:]
    // behavior holds the window action behavior choices.
    public var behavior: Behaviors = Behaviors()
    // snapping holds the drag snap configuration and footprint style.
    public var snapping: SnapChoices = SnapChoices()
    // stacking holds the cycling overlap offset and stack badge choices.
    public var stacking: StackChoices = StackChoices()
    // overlay holds the trigger key and grid size of the overlay that throws a window.
    public var overlay: OverlayChoices = OverlayChoices()
    // tiling holds the auto tiling mode and the main pane's share.
    public var tiling: TilingChoices = TilingChoices()
    // chains holds the saved action chains.
    public var chains: [Chain] = []
    // menu holds the menu order and the hidden actions.
    public var menu: MenuChoices = MenuChoices()
    // appRules holds the per-app rules applied when an app's first window appears.
    public var appRules: [AppRule] = []
    // profiles holds the saved profiles.
    public var profiles: [Profile] = []
    // activeProfile names the profile last applied, nil when none is.
    public var activeProfile: String?
    // slotStacks reports whether a slot holds every window of its app on the ultrawide, stacked,
    // instead of the main window alone.
    public var slotStacks: Bool = true
    // channelCycle reports whether Control-Left and Control-Right walk the channel's windows while the
    // front window fills the channel.
    public var channelCycle: Bool = true

    // init builds a set of choices.
    public init(
        slots: [SlotKey: String] = [:], widths: Widths? = nil, heights: Heights? = nil, paused: Bool = false,
        fullscreenFills: Bool = true, pinFullscreenFills: Bool = false
    ) {
        self.slots = slots
        self.widths = widths
        self.heights = heights
        self.paused = paused
        self.fullscreenFills = fullscreenFills
        self.pinFullscreenFills = pinFullscreenFills
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case slots, widths, heights, widthPresets, paused, fullscreenFills, pinFullscreenFills, keymap, shortcuts,
            sizes, gapPx
        case ignores, snap, workspaces, checkUpdates, mouseButtons, behavior, snapping, stacking
        case chains, menu, appRules, buttonClicks, profiles, activeProfile, overlay, tiling, slotStacks
        case channelCycle
    }

    // init decodes saved choices, skipping unknown slots and keeping what else is readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .slots)) ?? [:]
        slots = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in SlotKey(rawValue: k).map { ($0, v) } })
        widths = try? c.decodeIfPresent(Widths.self, forKey: .widths)
        heights = try? c.decodeIfPresent(Heights.self, forKey: .heights)
        widthPresets = (try? c.decodeIfPresent([Widths].self, forKey: .widthPresets)) ?? []
        paused = (try? c.decodeIfPresent(Bool.self, forKey: .paused)) ?? false
        fullscreenFills = (try? c.decodeIfPresent(Bool.self, forKey: .fullscreenFills)) ?? true
        pinFullscreenFills = (try? c.decodeIfPresent(Bool.self, forKey: .pinFullscreenFills)) ?? false
        keymap = (try? c.decodeIfPresent(String.self, forKey: .keymap)) ?? Keymap.rectangle.rawValue
        shortcuts = (try? c.decodeIfPresent([String: StoredShortcut?].self, forKey: .shortcuts)) ?? [:]
        sizes = (try? c.decodeIfPresent([StoredSize].self, forKey: .sizes)) ?? []
        gapPx = (try? c.decodeIfPresent(Double.self, forKey: .gapPx)) ?? 0
        ignores = (try? c.decodeIfPresent([String].self, forKey: .ignores)) ?? []
        snap = (try? c.decodeIfPresent(Bool.self, forKey: .snap)) ?? true
        workspaces = (try? c.decodeIfPresent([String: Workspace].self, forKey: .workspaces)) ?? [:]
        checkUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checkUpdates)) ?? true
        mouseButtons = (try? c.decodeIfPresent([String: String].self, forKey: .mouseButtons)) ?? [:]
        buttonClicks = (try? c.decodeIfPresent([String: String].self, forKey: .buttonClicks)) ?? [:]
        behavior = (try? c.decodeIfPresent(Behaviors.self, forKey: .behavior)) ?? Behaviors()
        snapping = (try? c.decodeIfPresent(SnapChoices.self, forKey: .snapping)) ?? SnapChoices()
        stacking = (try? c.decodeIfPresent(StackChoices.self, forKey: .stacking)) ?? StackChoices()
        overlay = (try? c.decodeIfPresent(OverlayChoices.self, forKey: .overlay)) ?? OverlayChoices()
        tiling = (try? c.decodeIfPresent(TilingChoices.self, forKey: .tiling)) ?? TilingChoices()
        chains = (try? c.decodeIfPresent([Chain].self, forKey: .chains)) ?? []
        menu = (try? c.decodeIfPresent(MenuChoices.self, forKey: .menu)) ?? MenuChoices()
        appRules = (try? c.decodeIfPresent([AppRule].self, forKey: .appRules)) ?? []
        profiles = (try? c.decodeIfPresent([Profile].self, forKey: .profiles)) ?? []
        activeProfile = try? c.decodeIfPresent(String.self, forKey: .activeProfile)
        slotStacks = (try? c.decodeIfPresent(Bool.self, forKey: .slotStacks)) ?? true
        channelCycle = (try? c.decodeIfPresent(Bool.self, forKey: .channelCycle)) ?? true
    }

    // encode writes the choices with slots keyed by slot name.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) }), forKey: .slots)
        try c.encodeIfPresent(widths, forKey: .widths)
        try c.encodeIfPresent(heights, forKey: .heights)
        try c.encode(widthPresets, forKey: .widthPresets)
        try c.encode(paused, forKey: .paused)
        try c.encode(fullscreenFills, forKey: .fullscreenFills)
        try c.encode(pinFullscreenFills, forKey: .pinFullscreenFills)
        try c.encode(keymap, forKey: .keymap)
        try c.encode(shortcuts, forKey: .shortcuts)
        try c.encode(sizes, forKey: .sizes)
        try c.encode(gapPx, forKey: .gapPx)
        try c.encode(ignores, forKey: .ignores)
        try c.encode(snap, forKey: .snap)
        try c.encode(workspaces, forKey: .workspaces)
        try c.encode(checkUpdates, forKey: .checkUpdates)
        try c.encode(mouseButtons, forKey: .mouseButtons)
        try c.encode(buttonClicks, forKey: .buttonClicks)
        try c.encode(behavior, forKey: .behavior)
        try c.encode(snapping, forKey: .snapping)
        try c.encode(stacking, forKey: .stacking)
        try c.encode(overlay, forKey: .overlay)
        try c.encode(tiling, forKey: .tiling)
        try c.encode(chains, forKey: .chains)
        try c.encode(menu, forKey: .menu)
        try c.encode(appRules, forKey: .appRules)
        try c.encode(profiles, forKey: .profiles)
        try c.encodeIfPresent(activeProfile, forKey: .activeProfile)
        try c.encode(slotStacks, forKey: .slotStacks)
        try c.encode(channelCycle, forKey: .channelCycle)
    }

    // restoringDefaults returns the default choices with the owner's own data kept: anchored apps, strip
    // sizes and width presets, the pause state, ignored apps, custom sizes, saved workspaces, chains, app rules and profiles.
    public func restoringDefaults() -> Choices {
        var c = Choices(slots: slots, widths: widths, heights: heights, paused: paused)
        c.widthPresets = widthPresets
        c.ignores = ignores
        c.sizes = sizes
        c.workspaces = workspaces
        c.chains = chains
        c.appRules = appRules
        c.profiles = profiles
        return c
    }

    // renameChain renames the chain at index to name and moves its shortcut, mouse buttons, button
    // clicks and menu entries to the new action name. It does nothing when index is out of range or another chain
    // already has the name.
    public mutating func renameChain(at index: Int, to name: String) {
        guard chains.indices.contains(index), !chains.contains(where: { $0.name == name }) else { return }
        let old = chains[index].actionName
        chains[index].name = name
        let new = chains[index].actionName
        if let sc = shortcuts.removeValue(forKey: old) {
            shortcuts[new] = sc
        }
        mouseButtons = mouseButtons.mapValues { $0 == old ? new : $0 }
        buttonClicks = buttonClicks.mapValues { $0 == old ? new : $0 }
        menu.order = menu.order.map { $0 == old ? new : $0 }
    }

    // encode returns choices as sorted JSON for saving.
    public static func encode(_ choices: Choices) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(choices)
    }

    // decode returns saved choices, or the defaults with the reason when data is empty or not
    // readable. A field that cannot be read takes its default and the rest still load, so a field
    // from a newer or older version never costs the others.
    public static func decode(_ data: Data) -> Loaded {
        guard !data.isEmpty else {
            return Loaded(choices: Choices(), fallback: "the saved choices are empty")
        }
        do {
            return Loaded(choices: try JSONDecoder().decode(Choices.self, from: data))
        } catch {
            return Loaded(choices: Choices(), fallback: "the saved choices are not readable: \(reason(error))")
        }
    }

    // reason writes a decoding error as its one-line description.
    private static func reason(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c), DecodingError.typeMismatch(_, let c),
            DecodingError.valueNotFound(_, let c), DecodingError.keyNotFound(_, let c):
            return c.debugDescription
        default:
            return "\(error)"
        }
    }
}

// Loaded is what a store read: the choices, and why they are the defaults when the saved ones could
// not be read.
public struct Loaded: Equatable, Sendable {
    // choices is what loaded, the defaults after a fallback.
    public var choices: Choices
    // fallback says why the saved choices were not used, nil when they were or none were saved.
    public var fallback: String?

    // init builds a load result.
    public init(choices: Choices, fallback: String? = nil) {
        self.choices = choices
        self.fallback = fallback
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
    public init(
        id: WindowID, bundle: String, frame: Frame, onUltrawide: Bool, isMain: Bool,
        isFilePanel: Bool = false, isFullScreen: Bool = false, zoomRect: Frame? = nil
    ) {
        self.id = id
        self.bundle = bundle
        self.frame = frame
        self.onUltrawide = onUltrawide
        self.isMain = isMain
        self.isFilePanel = isFilePanel
        self.isFullScreen = isFullScreen
        self.zoomRect = zoomRect
    }

    // promotingLone marks an app's one on-screen window as its main window when the app names none
    // of its on-screen windows main, so a pin holds an app whose main window is off screen. An open
    // or save panel is never promoted.
    public static func promotingLone(_ windows: [WindowInfo]) -> [WindowInfo] {
        var counts: [String: Int] = [:]
        var hasMain: Set<String> = []
        for w in windows where !w.isFilePanel {
            counts[w.bundle, default: 0] += 1
            if w.isMain {
                hasMain.insert(w.bundle)
            }
        }
        return windows.map { w in
            guard !w.isMain, !w.isFilePanel, counts[w.bundle] == 1, !hasMain.contains(w.bundle) else { return w }
            var out = w
            out.isMain = true
            return out
        }
    }

    // carrying returns the windows of last still on screen, each moved to its frame in frames with
    // its green button alongside, for an app too busy to answer a pass.
    public static func carrying(_ last: [WindowInfo], frames: [WindowID: Frame]) -> [WindowInfo] {
        last.compactMap { w in
            guard let f = frames[w.id] else { return nil }
            var out = w
            out.frame = f
            out.zoomRect = w.zoomRect.map {
                Frame(x: $0.x + f.x - w.frame.x, y: $0.y + f.y - w.frame.y, w: $0.w, h: $0.h)
            }
            return out
        }
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
    public init(id: WindowID, frame: Frame, target: Frame? = nil, anchor: Edges = Edges(), exitFullScreen: Bool = false)
    {
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
    // titleBand is how much of a free window's top stays on the channel when it hangs off the bottom.
    static let titleBand = 40.0
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
    // lastChannel is the channel of the last pass, nil before the first.
    var lastChannel: Frame?
    // castOff holds the windows let free over the strips.
    var castOff: Set<WindowID> = []
    // stashed holds the windows parked at a screen edge, which the channel never pulls back in.
    public var stashed: Set<WindowID> = []
    // bursts counts recent moves per window.
    var bursts: [WindowID: Burst] = [:]
    // holders maps each pinned bundle to its pin's holder, the window the menu and remoor name.
    var holders: [String: WindowID] = [:]
    // held maps each window a pin held in the last pass to the pin's bundle.
    var held: [WindowID: String] = [:]
    // holdAreas maps each window a pin held in the last pass to the frame the pin keeps it in.
    var holdAreas: [WindowID: Frame] = [:]
    // parts maps each held window an action placed inside its slot to that part of the slot.
    var parts: [WindowID: SlotPart] = [:]
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
    // history holds the frames each window was moved away from, for undo-move and redo-move.
    public var history = History()
    // floors records the smallest size each window was seen to keep.
    var floors: [WindowID: Floor] = [:]
    // dragging reports whether a pass saw the mouse button down since the last pass that acted.
    var dragging = false
    // seenAt records where each free window was left by the last pass that acted.
    var seenAt: [WindowID: Frame] = [:]
    // hung holds the free windows the owner dropped by hand, which may hang off the channel bottom.
    var hung: Set<WindowID> = []
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

    // splitSides returns the sides where two anchored apps keep their strip, so each takes a row.
    public func splitSides() -> [Side] {
        let held = pins().filter { holdsSpace($0.bundle) }.map(\.slot.side)
        return [Side.left, .right].filter { side in held.filter { $0 == side }.count > 1 }
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
        strip(screen, key.side, key.row)
    }

    // strip returns row of the strip on side, the whole strip when row is nil, at the side's width,
    // the chosen width when the side is empty.
    func strip(_ screen: Frame, _ side: Side, _ row: Row?) -> Frame {
        let use = inUse(screen)
        let pct = side == .left ? (use.left > 0 ? use.left : widths.left) : (use.right > 0 ? use.right : widths.right)
        return Geometry.slot(screen, side, row, pct, topPct: heights[side])
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

    // pinsWindow reports whether pin holds w. The pin's holder is the window it already holds, or
    // else the app's main window, which it then keeps. With slotStacks on, the pin also holds every
    // other window of the app on the ultrawide, stacked in the slot; with it off they are kept in the
    // channel like any free window. An open or save panel is never held.
    func pinsWindow(_ pin: Pin, _ w: WindowInfo) -> Bool {
        if let held = holders[pin.bundle] {
            if held == w.id {
                return true
            }
        } else if w.isMain && !w.isFilePanel && !w.isFullScreen {
            holders[pin.bundle] = w.id
            return true
        }
        return choices.slotStacks && w.onUltrawide && !w.isFilePanel
    }

    // claim gives each pin without a holder the front-most window of its app that lies inside the
    // pin's strip, so the window the owner sees anchored keeps the pin when the old holder closed or
    // moorings just started. A pin with no window there is left to pinsWindow, which takes the main
    // window.
    func claim(_ windows: [WindowInfo], _ pins: [Pin], _ screen: Frame) {
        for pin in pins where holders[pin.bundle] == nil {
            let area = strip(screen, pin.slot.side, nil)
            let w = windows.first {
                $0.bundle == pin.bundle && $0.onUltrawide && !$0.isFilePanel && !$0.isFullScreen
                    && Self.within($0.frame, area)
            }
            if let w {
                holders[pin.bundle] = w.id
            }
        }
    }

    // within reports whether frame f lies inside area, give or take tolerance on each edge.
    static func within(_ f: Frame, _ area: Frame) -> Bool {
        f.x >= area.x - tolerance && f.y >= area.y - tolerance
            && f.x + f.w <= area.x + area.w + tolerance && f.y + f.h <= area.y + area.h + tolerance
    }

    // slotWindows returns the windows the pin in slot key held in the last pass, in id order.
    public func slotWindows(_ key: SlotKey) -> [WindowID] {
        guard let bundle = choices.slots[key] else { return [] }
        return held.filter { $0.value == bundle }.keys.sorted()
    }

    // actionArea returns the area a position action on the window with id works in: the frame its
    // pin held it in during the last pass, else area.
    public func actionArea(_ id: WindowID, else area: Frame) -> Frame {
        holdAreas[id] ?? area
    }

    // holdPart keeps the held window with id at frame, the part of its slot an action named name
    // chose, until the window closes or the part is cleared. It reports whether the window is held.
    @discardableResult
    public func holdPart(_ id: WindowID, _ name: String, _ frame: Frame) -> Bool {
        guard let area = holdAreas[id], area.w > 0, area.h > 0 else { return false }
        let unit = Frame(
            x: (frame.x - area.x) / area.w, y: (frame.y - area.y) / area.h,
            w: frame.w / area.w, h: frame.h / area.h)
        parts[id] = SlotPart(name: name, unit: unit)
        placed[id] = nil
        return true
    }

    // clearPart gives the window with id its whole slot again on the next pass, and reports whether
    // it had a part.
    @discardableResult
    public func clearPart(_ id: WindowID) -> Bool {
        guard parts.removeValue(forKey: id) != nil else { return false }
        placed[id] = nil
        return true
    }

    // part returns the part of its slot the window with id is held at, nil for the whole slot.
    public func part(_ id: WindowID) -> SlotPart? {
        parts[id]
    }

    // nextSlotWindow returns the window after id, or before it when backward, among the windows its
    // slot held in the last pass, wrapping at the ends. It is nil when id is not held or is alone.
    public func nextSlotWindow(after id: WindowID, backward: Bool = false) -> WindowID? {
        guard let bundle = held[id], let key = pin(bundle)?.slot else { return nil }
        let list = slotWindows(key)
        guard list.count > 1, let i = list.firstIndex(of: id) else { return nil }
        return list[(i + (backward ? list.count - 1 : 1)) % list.count]
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

    // prune forgets cast-off, stashed and saved windows that no longer exist, so a later window with
    // a reused id is held in the channel and undo is not offered for a closed window.
    public func prune(alive: Set<WindowID>) {
        castOff.formIntersection(alive)
        stashed.formIntersection(alive)
        saved = saved.filter { alive.contains($0.key) }
        parts = parts.filter { alive.contains($0.key) }
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

    // spans reports whether frame f reaches past both edges of channel ch, as a window macOS zoomed
    // to the whole display does.
    static func spans(_ f: Frame, _ ch: Frame) -> Bool {
        f.x < ch.x - tolerance && f.x + f.w > ch.x + ch.w + tolerance
    }

    // keep returns f no wider or taller than channel ch and between its side edges. Below ch's top
    // it stays where it is when open, so a window the owner dragged down hangs off the screen as
    // macOS allows with at least titleBand of its top on the channel. Otherwise f is kept wholly
    // inside ch, so an app that grows its own window past the bottom keeps its controls on screen.
    static func keep(_ f: Frame, _ ch: Frame, open: Bool) -> Frame {
        var k = Geometry.clamp(f, ch)
        if open {
            k.y = max(ch.y, min(f.y, ch.y + ch.h - min(k.h, titleBand)))
        }
        return k
    }

    // drop marks free window w as hung when it moved since the last pass while the mouse button was
    // down, so the owner dragged it, and clears the mark when anything else moved it. It records
    // where w is now; settle overwrites that with any move it makes.
    func drop(_ w: WindowInfo, dropped: Bool) {
        if let last = seenAt[w.id], !Actions.near(last, w.frame, tolerance: Self.tolerance) {
            if dropped {
                hung.insert(w.id)
            } else {
                hung.remove(w.id)
            }
        }
        seenAt[w.id] = w.frame
    }

    // settle keeps free window w inside channel ch, and lets a window the channel once narrowed grow
    // back toward its own width when the channel widens. A zoomed window is the owner's own request,
    // so pulling it back never counts toward a hold. When the channel moved from old, a window on
    // its old edges that the channel did not narrow follows them: one filling it keeps filling it,
    // and one on a single edge slides with that edge at its own width. A window in hung may hang
    // off the bottom.
    func settle(_ w: WindowInfo, _ ch: Frame, zoomed: Bool = false, old: Frame? = nil) -> Move? {
        let open = hung.contains(w.id)
        if zoomed {
            bursts[w.id] = nil
        }
        let narrowed = clamped[w.id].map { abs(w.frame.w - $0.set) <= Self.tolerance } ?? false
        if let old, !narrowed, !Actions.near(old, ch, tolerance: Self.tolerance) {
            let left = abs(w.frame.x - old.x) <= Self.tolerance
            let right = abs(w.frame.x + w.frame.w - (old.x + old.w)) <= Self.tolerance
            if left || right {
                var f = w.frame
                if left && right {
                    f.x = ch.x
                    f.w = ch.w
                } else {
                    f.x = left ? ch.x : ch.x + ch.w - f.w
                }
                clamped[w.id] = nil
                return place(w, Self.keep(f, ch, open: open))
            }
        }
        var c = clamped[w.id]
        if let current = c, abs(w.frame.w - current.set) > Self.tolerance {
            c = nil
        }
        var f = w.frame
        if let c {
            f.w = c.natural
        }
        let want = Self.keep(f, ch, open: open)
        clamped[w.id] = want.w < f.w ? Clamp(natural: f.w, set: want.w) : nil
        return place(w, want)
    }

    // moor returns the moves that put every pin in its slot, or over the channel while lifted, and
    // every free window on the ultrawide in the channel. An anchored app's other windows are free
    // windows, and an open or save panel is never moved. A pin the owner moved by hand is released
    // and left alone. Native fullscreen is turned back into a slot or a channel fill when the
    // choices say so. Nothing moves while paused, while the mouse button is down, or without an
    // ultrawide.
    public func moor(_ scene: Scene) -> [Move] {
        justReleased = []
        if choices.paused {
            placed = [:]
            held = [:]
            holdAreas = [:]
            return []
        }
        if scene.mouseHeld {
            dragging = true
        }
        guard !scene.mouseHeld, let screen = scene.screen else { return [] }
        let dropped = dragging
        dragging = false
        now = scene.now
        let pins = pins()
        var shown: Set<String> = []
        held = [:]
        holdAreas = [:]
        holders = holders.filter { id in scene.windows.contains { $0.id == id.value } }
        claim(scene.windows, pins, screen)
        for w in scene.windows {
            if let pin = pin(w.bundle, in: pins), pinsWindow(pin, w) {
                shown.insert(pin.bundle)
                held[w.id] = pin.bundle
            }
        }
        present = shown
        for bundle in shown {
            openedAt[bundle] = nil
        }
        let rows = rows(pins.filter { holdsSpace($0.bundle) })
        for w in scene.windows {
            doubt(w)
        }
        measure(scene.windows, pins)
        let use = inUse(screen)
        let h = heights
        let ch = Geometry.regions(screen, use.left, use.right).channel
        let old = lastChannel
        lastChannel = ch
        var moves: [Move] = []
        var seen: Set<WindowID> = []
        for w in scene.windows {
            seen.insert(w.id)
            if let pin = pin(w.bundle, in: pins), pinsWindow(pin, w) {
                // Only the window the pin held is sent back from native fullscreen. Another window
                // of the app, such as a video player's fullscreen window, is left alone.
                if w.isFullScreen {
                    if choices.pinFullscreenFills, holders[pin.bundle] == w.id,
                        let exit = leaveFullScreen(w)
                    {
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
                let area = Geometry.slot(screen, side, row, pct, topPct: h[side])
                holdAreas[w.id] = area
                let target =
                    lifted.contains(w.id)
                    ? Geometry.lift(screen, side, use.left, use.right)
                    : parts[w.id].map { $0.frame(in: area) } ?? area
                if let move = moorPin(w, target, Edges(right: side == .right, bottom: row == .bottom)) {
                    moves.append(move)
                }
            } else if w.onUltrawide, !w.isFilePanel {
                // A window no pin holds has no slot place to keep, so a later hold starts fresh
                // instead of reading its time in the channel as a move by hand.
                placed[w.id] = nil
                parts[w.id] = nil
                released.remove(w.id)
                cap(w.id, ch)
                drop(w, dropped: dropped)
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
                } else if stashed.contains(w.id) {
                    clamped[w.id] = nil
                } else if castOff.contains(w.id) {
                    // A cast-off window loses its clamped width, so it never grows back to it later.
                    clamped[w.id] = nil
                    cacheZoom(w, w.frame, free: true)
                } else if let move = settle(w, ch, zoomed: w.id == scene.focused && Self.spans(w.frame, ch), old: old) {
                    seenAt[w.id] = move.frame
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
        seenAt = seenAt.filter { seen.contains($0.key) }
        hung.formIntersection(seen)
        released.formIntersection(seen)
        lifted.formIntersection(seen)
        return moves
    }

    // pin returns the pin in pins for bundle, or nil.
    private func pin(_ bundle: String, in pins: [Pin]) -> Pin? {
        pins.first { $0.bundle == bundle }
    }
}
