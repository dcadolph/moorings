import Foundation

// Modifier is a shortcut modifier. The cases are in the order macOS menus show them.
public enum Modifier: String, CaseIterable, Comparable, Sendable {
    case ctrl, alt, shift, cmd

    // glyph is the menu glyph of the modifier.
    public var glyph: String {
        switch self {
        case .ctrl: return "⌃"
        case .alt: return "⌥"
        case .shift: return "⇧"
        case .cmd: return "⌘"
        }
    }

    // word is the name printed on the modifier's key.
    public var word: String {
        switch self {
        case .ctrl: return "Control"
        case .alt: return "Option"
        case .shift: return "Shift"
        case .cmd: return "Command"
        }
    }

    // aliases maps the other names a config may use to one spelling.
    private static let aliases: [String: Modifier] = [
        "control": .ctrl, "option": .alt, "opt": .alt, "command": .cmd,
    ]

    // parse resolves a config spelling, ignoring case and accepting aliases, or returns nil.
    public static func parse(_ name: String) -> Modifier? {
        let lower = name.lowercased()
        return aliases[lower] ?? Modifier(rawValue: lower)
    }

    // < orders modifiers the way macOS menus show them.
    public static func < (a: Modifier, b: Modifier) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

// Shortcut is a resolved key binding: modifiers in menu order without repeats, and a lowercase key.
public struct Shortcut: Equatable, Sendable {
    // mods are the modifiers in menu order.
    public var mods: [Modifier]
    // key is the key name, such as left, delete or u.
    public var key: String

    // init builds a shortcut, putting mods in menu order and dropping repeats.
    public init(mods: [Modifier], key: String) {
        self.mods = Array(Set(mods)).sorted()
        self.key = key
    }

    // keyGlyphs maps a key name to its menu glyph.
    private static let keyGlyphs: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "delete": "⌫",
        "forwarddelete": "⌦", "space": "Space", "tab": "⇥", "escape": "⎋",
    ]

    // keyNames maps a key name to the name printed on its key.
    private static let keyNames: [String: String] = [
        "left": "Left Arrow", "right": "Right Arrow", "up": "Up Arrow", "down": "Down Arrow",
        "return": "Return", "delete": "Delete", "forwarddelete": "Forward Delete", "space": "Space",
        "tab": "Tab", "escape": "Escape",
    ]

    // text returns the menu glyphs of the shortcut, such as ⌃⌥←.
    public var text: String {
        mods.map(\.glyph).joined() + (Shortcut.keyGlyphs[key] ?? key.uppercased())
    }

    // words returns the shortcut spelled out, such as Control-Option-Delete.
    public var words: String {
        (mods.map(\.word) + [Shortcut.keyNames[key] ?? key.uppercased()]).joined(separator: "-")
    }

    // spelled returns the shortcut spelled out with its glyphs after it, such as
    // Control-Option-Delete (⌃⌥⌫), the way every message names a shortcut.
    public var spelled: String {
        "\(words) (\(text))"
    }
}

// ShortcutInput is a shortcut as written in the config: modifier names that may be unknown, and a
// key. A nil field is a missing one.
public struct ShortcutInput: Equatable, Sendable {
    // mods are the modifier names as written.
    public var mods: [String]?
    // key is the key name as written.
    public var key: String?

    // init builds an input.
    public init(mods: [String]? = nil, key: String? = nil) {
        self.mods = mods
        self.key = key
    }

    // wellFormed reports whether the input has both modifiers and a key.
    var wellFormed: Bool { mods != nil && key != nil }
}

// Binding is a config entry for one action's shortcut: a shortcut to set or false to remove it.
public enum Binding: Equatable, Sendable {
    case remove
    case set(ShortcutInput)
}

// ConfigNumber is a config value that should be a number: missing, a number, or something else.
public enum ConfigNumber: Equatable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    case absent
    case number(Double)
    case other

    // init builds a number from an integer literal.
    public init(integerLiteral value: Int) { self = .number(Double(value)) }

    // init builds a number from a float literal.
    public init(floatLiteral value: Double) { self = .number(value) }

    // value returns the number, or nil when the value is missing or not a number.
    var value: Double? {
        if case let .number(n) = self { return n }
        return nil
    }
}

// SizeEntry is one custom size as written in the config.
public struct SizeEntry: Equatable, Sendable {
    // title names the size and its action.
    public var title: String?
    // x is the share of the width before the left edge.
    public var x: ConfigNumber
    // y is the share of the height above the top edge.
    public var y: ConfigNumber
    // w is the share of the width.
    public var w: ConfigNumber
    // h is the share of the height.
    public var h: ConfigNumber
    // width is an optional width in points.
    public var width: ConfigNumber
    // height is an optional height in points.
    public var height: ConfigNumber
    // shortcut is the size's own shortcut, if any.
    public var shortcut: ShortcutInput?

    // init builds an entry with every field missing unless given.
    public init(
        title: String? = nil, x: ConfigNumber = .absent, y: ConfigNumber = .absent,
        w: ConfigNumber = .absent, h: ConfigNumber = .absent, width: ConfigNumber = .absent,
        height: ConfigNumber = .absent, shortcut: ShortcutInput? = nil
    ) {
        self.title = title
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.width = width
        self.height = height
        self.shortcut = shortcut
    }
}

// CustomSize is a valid custom size with its action name.
public struct CustomSize: Equatable, Sendable {
    // name is the action name, size: followed by the title.
    public var name: String
    // spec is the size's geometry.
    public var spec: CustomSpec
    // shortcut is the size's own shortcut, if any.
    public var shortcut: ShortcutInput?
}

// SizesResult holds the valid custom sizes in config order and the problems found.
public struct SizesResult: Equatable, Sendable {
    // sizes are the valid sizes in config order.
    public var sizes: [CustomSize]
    // problems describes each rejected entry.
    public var problems: [String]

    // specs maps each valid size's action name to its geometry.
    public var specs: [String: CustomSpec] {
        Dictionary(sizes.map { ($0.name, $0.spec) }, uniquingKeysWith: { first, _ in first })
    }
}

// ShortcutsResult holds the bound shortcuts by action name and the problems found.
public struct ShortcutsResult: Equatable, Sendable {
    // map is the shortcut of each bound action.
    public var map: [String: Shortcut]
    // problems describes each ignored or clashing entry.
    public var problems: [String]
}

// Keymap names a built-in shortcut set.
public enum Keymap: String, CaseIterable, Sendable {
    // rectangle is Rectangle's recommended set.
    case rectangle
    // spectacle is Spectacle's default set.
    case spectacle
    // magnet is Magnet's default set.
    case magnet
    // windows is the Rectangle set with Control-Option arrows on Arrow mode.
    case windows
    // none binds no shortcut.
    case none

    // names lists the built-in keymaps in menu order.
    public static let names = allCases.map(\.rawValue)

    // table returns the keymap's default shortcut of each action.
    public var table: [String: Shortcut] {
        switch self {
        case .rectangle: return Keymap.rectangleTable
        case .spectacle: return Keymap.spectacleTable
        case .magnet: return Keymap.magnetTable
        case .windows: return Keymap.windowsTable
        case .none: return [:]
        }
    }

    // windowsTable is the Rectangle set without the four halves, which Control-Option arrows run as
    // Arrow mode instead.
    private static let windowsTable: [String: Shortcut] = {
        var t = rectangleTable
        for name in ["left-half", "right-half", "top-half", "bottom-half"] { t[name] = nil }
        for dir in ["left", "right", "up", "down"] { t["arrow-" + dir] = sc([.ctrl, .alt], dir) }
        return t
    }()

    // sc builds a shortcut from modifiers and a key.
    private static func sc(_ mods: [Modifier], _ key: String) -> Shortcut {
        Shortcut(mods: mods, key: key)
    }

    // rectangleTable is Rectangle's recommended set.
    private static let rectangleTable: [String: Shortcut] = [
        "left-half": sc([.ctrl, .alt], "left"),
        "right-half": sc([.ctrl, .alt], "right"),
        "top-half": sc([.ctrl, .alt], "up"),
        "bottom-half": sc([.ctrl, .alt], "down"),
        "top-left": sc([.ctrl, .alt], "u"),
        "top-right": sc([.ctrl, .alt], "i"),
        "bottom-left": sc([.ctrl, .alt], "j"),
        "bottom-right": sc([.ctrl, .alt], "k"),
        "first-third": sc([.ctrl, .alt], "d"),
        "center-third": sc([.ctrl, .alt], "f"),
        "last-third": sc([.ctrl, .alt], "g"),
        "first-two-thirds": sc([.ctrl, .alt], "e"),
        "center-two-thirds": sc([.ctrl, .alt], "r"),
        "last-two-thirds": sc([.ctrl, .alt], "t"),
        "maximize": sc([.ctrl, .alt], "return"),
        "maximize-height": sc([.ctrl, .alt, .shift], "up"),
        "center": sc([.ctrl, .alt], "c"),
        "larger": sc([.ctrl, .alt], "="),
        "smaller": sc([.ctrl, .alt], "-"),
        "restore": sc([.ctrl, .alt], "delete"),
        "previous-display": sc([.ctrl, .alt, .cmd], "left"),
        "next-display": sc([.ctrl, .alt, .cmd], "right"),
        "cycle-slot-windows": sc([.ctrl, .alt, .cmd], "down"),
        "cycle-slot-windows-backward": sc([.ctrl, .alt, .cmd], "up"),
    ]

    // magnetTable is Magnet's default set: the Control-Option keys Rectangle's alternate set ships for
    // Magnet users, without the larger, smaller, maximize height and center two thirds keys Magnet
    // does not have.
    private static let magnetTable: [String: Shortcut] = [
        "left-half": sc([.ctrl, .alt], "left"),
        "right-half": sc([.ctrl, .alt], "right"),
        "top-half": sc([.ctrl, .alt], "up"),
        "bottom-half": sc([.ctrl, .alt], "down"),
        "top-left": sc([.ctrl, .alt], "u"),
        "top-right": sc([.ctrl, .alt], "i"),
        "bottom-left": sc([.ctrl, .alt], "j"),
        "bottom-right": sc([.ctrl, .alt], "k"),
        "first-third": sc([.ctrl, .alt], "d"),
        "center-third": sc([.ctrl, .alt], "f"),
        "last-third": sc([.ctrl, .alt], "g"),
        "first-two-thirds": sc([.ctrl, .alt], "e"),
        "last-two-thirds": sc([.ctrl, .alt], "t"),
        "maximize": sc([.ctrl, .alt], "return"),
        "center": sc([.ctrl, .alt], "c"),
        "restore": sc([.ctrl, .alt], "delete"),
        "previous-display": sc([.ctrl, .alt, .cmd], "left"),
        "next-display": sc([.ctrl, .alt, .cmd], "right"),
    ]

    // spectacleTable is Spectacle's default set. Its next and previous third walk the thirds, which
    // first-third and last-third do on a repeat press.
    private static let spectacleTable: [String: Shortcut] = [
        "center": sc([.alt, .cmd], "c"),
        "maximize": sc([.alt, .cmd], "f"),
        "left-half": sc([.alt, .cmd], "left"),
        "right-half": sc([.alt, .cmd], "right"),
        "top-half": sc([.alt, .cmd], "up"),
        "bottom-half": sc([.alt, .cmd], "down"),
        "top-left": sc([.ctrl, .cmd], "left"),
        "bottom-left": sc([.ctrl, .shift, .cmd], "left"),
        "top-right": sc([.ctrl, .cmd], "right"),
        "bottom-right": sc([.ctrl, .shift, .cmd], "right"),
        "next-display": sc([.ctrl, .alt, .cmd], "right"),
        "previous-display": sc([.ctrl, .alt, .cmd], "left"),
        "first-third": sc([.ctrl, .alt], "right"),
        "last-third": sc([.ctrl, .alt], "left"),
        "larger": sc([.ctrl, .alt, .shift], "right"),
        "smaller": sc([.ctrl, .alt, .shift], "left"),
        "restore": sc([.alt, .cmd], "z"),
    ]
}

// Keymaps holds the shortcut tables, parsing and validation. Every function is pure.
public enum Keymaps {
    // sizePrefix starts the action name of every custom size.
    public static let sizePrefix = "size:"

    // workspacePrefix starts the action name that recalls a saved workspace.
    public static let workspacePrefix = "workspace:"

    // menuName is the action that opens the moorings menu under the pointer.
    public static let menuName = "show-menu"

    // stripsName is the action that opens the on-screen strip editor.
    public static let stripsName = "adjust-strips"

    // maxGap is the widest gap the config may ask for.
    public static let maxGap = 100.0

    // special lists the actions that are not positions in geometry.
    private static let special: Set<String> = [
        "larger", "smaller", "restore", "undo-move", "redo-move", "next-display", "previous-display",
    ]

    // organizeNames returns the organize actions in menu order.
    public static let organizeNames = [
        "tile-columns", "tile-rows", "tile-all", "tile-active-app", "cascade-all", "cascade-active-app",
        "cycle-stacked-windows", "cycle-stacked-windows-backward", "cycle-slot-windows",
        "cycle-slot-windows-backward", "reverse-all",
    ]

    // windowNames lists the actions on the front app's windows that never move a frame, in menu order.
    public static let windowNames = [
        "focus-next-window", "focus-previous-window", "minimize-window", "close-window", "minimize-others",
        "close-others",
    ]

    // stashNames lists the stash actions, in menu order.
    public static let stashNames = ["stash", "unstash-all"]

    // known reports whether name is an action moorings can run. A workspace or chain name counts,
    // since both are saved after the shortcuts are bound.
    public static func known(_ name: String) -> Bool {
        special.contains(name) || organizeNames.contains(name) || windowNames.contains(name)
            || stashNames.contains(name) || Tiling.handles(name) || Actions.arrowNames.contains(name)
            || Actions.fillNames.contains(name)
            || name == Actions.specifiedName || Actions.displayNames.contains(name)
            || (name.hasPrefix(workspacePrefix) && name.count > workspacePrefix.count)
            || (name.hasPrefix(Profile.prefix) && name.count > Profile.prefix.count)
            || (name.hasPrefix(Chain.prefix) && name.count > Chain.prefix.count) || name == menuName
            || name == stripsName
            || Overlay.gridSize(name, OverlayChoices()) != nil
            || Geometry.position(name, Frame(x: 0, y: 0, w: 100, h: 100)) != nil
    }

    // label turns an action name into menu text, so left-half reads Left half and a custom size
    // reads as its title.
    public static func label(_ name: String) -> String {
        if name.hasPrefix(sizePrefix) {
            return String(name.dropFirst(sizePrefix.count))
        }
        if name.hasPrefix(Chain.prefix) {
            return String(name.dropFirst(Chain.prefix.count))
        }
        if name == menuName {
            return "Moorings menu at the pointer"
        }
        if name == stripsName {
            return "Adjust strips"
        }
        if let mode = Tiling.mode(name) {
            return mode == .off ? "Tiling off" : mode == .bsp ? "BSP layout" : mode.rawValue.capitalized + " layout"
        }
        if name.hasPrefix(Overlay.gridPrefix), let size = Overlay.gridSize(name, OverlayChoices()) {
            return "Grid \(size.cols) by \(size.rows)"
        }
        let s = name.replacingOccurrences(of: "-", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // share reports whether v is missing or a number from lo to 1.
    private static func share(_ v: ConfigNumber, _ lo: Double) -> Bool {
        switch v {
        case .absent: return true
        case let .number(n): return n >= lo && n <= 1
        case .other: return false
        }
    }

    // points reports whether v is missing or a positive number.
    private static func points(_ v: ConfigNumber) -> Bool {
        switch v {
        case .absent: return true
        case let .number(n): return n > 0
        case .other: return false
        }
    }

    // sizes checks the custom sizes from the config and returns the valid ones, each with its
    // action name, plus the problems found.
    public static func sizes(_ list: [SizeEntry]) -> SizesResult {
        var out: [CustomSize] = []
        var problems: [String] = []
        var seen = Set<String>()
        for (i, e) in list.enumerated() {
            guard let title = e.title, !title.isEmpty else {
                problems.append("sizes entry \(i + 1) needs a title: ignoring it")
                continue
            }
            let fitX = (e.x.value ?? 0) + (e.w.value ?? 1)
            let fitY = (e.y.value ?? 0) + (e.h.value ?? 1)
            if seen.contains(title) {
                problems.append("sizes has two entries titled \(title): the first wins")
            } else if !(share(e.x, 0) && share(e.y, 0) && share(e.w, 1e-9) && share(e.h, 1e-9))
                || fitX > 1 + 1e-9 || fitY > 1 + 1e-9
            {
                problems.append("size \(title) needs x, y, w and h between 0 and 1 that fit the area: ignoring it")
            } else if !(points(e.width) && points(e.height)) {
                problems.append("size \(title) needs a width and height above 0: ignoring it")
            } else {
                seen.insert(title)
                let spec = CustomSpec(
                    x: e.x.value ?? 0, y: e.y.value ?? 0, w: e.w.value ?? 1, h: e.h.value ?? 1,
                    width: e.width.value, height: e.height.value
                )
                out.append(CustomSize(name: sizePrefix + title, spec: spec, shortcut: e.shortcut))
            }
        }
        return SizesResult(sizes: out, problems: problems)
    }

    // gap returns the gap between windows in points from the config, and the problem found. A
    // missing value is 0 without a problem.
    public static func gap(_ value: ConfigNumber) -> (points: Double, problem: String?) {
        switch value {
        case .absent:
            return (0, nil)
        case let .number(g) where g >= 0 && g <= maxGap:
            return (g.rounded(.down), nil)
        default:
            return (0, "gapPx must be a number from 0 to \(Int(maxGap)): using 0")
        }
    }

    // resolveMods returns mods with aliases resolved, or nil when one is unknown.
    private static func resolveMods(_ mods: [String]) -> [Modifier]? {
        var out: [Modifier] = []
        for m in mods {
            guard let mod = Modifier.parse(m) else { return nil }
            out.append(mod)
        }
        return out
    }

    // shortcuts merges overrides and extra onto keymap and returns the binding for each action plus
    // the problems found. extra maps more action names, such as custom sizes, to their shortcuts,
    // and also makes those names valid in overrides. A remove binding drops a shortcut. When two
    // actions share a key, one the config set beats a default, and otherwise the first in name
    // order keeps it.
    public static func shortcuts(
        _ overrides: [String: Binding] = [:], extra: [String: Binding] = [:], keymap: Keymap = .rectangle
    ) -> ShortcutsResult {
        var merged: [String: ShortcutInput] = [:]
        var explicit = Set<String>()
        var problems: [String] = []
        for (name, sc) in keymap.table {
            merged[name] = ShortcutInput(mods: sc.mods.map(\.rawValue), key: sc.key)
        }
        for (name, binding) in extra.sorted(by: { $0.key < $1.key }) {
            if case let .set(sc) = binding, sc.wellFormed {
                merged[name] = sc
                explicit.insert(name)
            } else if case .set = binding {
                problems.append("shortcut for \(name) needs mods and key: ignoring it")
            }
        }
        for (name, binding) in overrides.sorted(by: { $0.key < $1.key }) {
            if !(known(name) || extra[name] != nil) {
                problems.append("shortcuts names unknown action \(name): ignoring it")
            } else if case let .set(sc) = binding {
                if sc.wellFormed {
                    merged[name] = sc
                    explicit.insert(name)
                } else {
                    problems.append("shortcut for \(name) needs mods and key: ignoring it")
                }
            } else {
                merged[name] = nil
            }
        }
        let names = merged.keys.sorted { a, b in
            if explicit.contains(a) != explicit.contains(b) {
                return explicit.contains(a)
            }
            return a < b
        }
        var out: [String: Shortcut] = [:]
        var owner: [String: String] = [:]
        for name in names {
            guard let input = merged[name], let mods = resolveMods(input.mods ?? []), let key = input.key else {
                problems.append("shortcut for \(name) has an unknown modifier: ignoring it")
                continue
            }
            let sc = Shortcut(mods: mods, key: key.lowercased())
            if let first = owner[sc.text] {
                problems.append("\(first) and \(name) share \(sc.text): \(first) keeps it")
            } else {
                owner[sc.text] = name
                out[name] = sc
            }
        }
        return ShortcutsResult(map: out, problems: problems)
    }
}

// StoredShortcut is a shortcut as the choices save it.
public struct StoredShortcut: Codable, Equatable, Sendable {
    // mods names the modifier keys.
    public var mods: [String]
    // key names the key.
    public var key: String

    // init builds a saved shortcut.
    public init(mods: [String], key: String) {
        self.mods = mods
        self.key = key
    }

    // input returns the shortcut in the form Keymaps checks.
    public var input: ShortcutInput { ShortcutInput(mods: mods, key: key) }
}

// StoredSize is a custom size as the choices save it: shares of the area, or points.
public struct StoredSize: Codable, Equatable, Sendable {
    // title names the size in the menu.
    public var title: String
    // x is the share of the width before the left edge.
    public var x: Double?
    // y is the share of the height above the top edge.
    public var y: Double?
    // w is the share of the width.
    public var w: Double?
    // h is the share of the height.
    public var h: Double?
    // width is a width in points.
    public var width: Double?
    // height is a height in points.
    public var height: Double?
    // shortcut is the size's shortcut, nil when it has none.
    public var shortcut: StoredShortcut?

    // init builds a saved size.
    public init(
        title: String, x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil,
        width: Double? = nil, height: Double? = nil, shortcut: StoredShortcut? = nil
    ) {
        self.title = title
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.width = width
        self.height = height
        self.shortcut = shortcut
    }

    // entry returns the size in the form Keymaps checks.
    public var entry: SizeEntry {
        let n = { (v: Double?) -> ConfigNumber in v.map { .number($0) } ?? .absent }
        return SizeEntry(
            title: title, x: n(x), y: n(y), w: n(w), h: n(h), width: n(width), height: n(height),
            shortcut: shortcut?.input)
    }
}

// Bindings is every shortcut and custom size in effect for a set of choices.
public struct Bindings: Equatable, Sendable {
    // map is the shortcut for each action.
    public var map: [String: Shortcut]
    // sizes lists the valid custom sizes in menu order.
    public var sizes: [CustomSize]
    // problems lists what was wrong with the saved shortcuts and sizes.
    public var problems: [String]

    // init works out the bindings for choices.
    public init(_ choices: Choices) {
        let sized = Keymaps.sizes(choices.sizes.map(\.entry))
        var extra: [String: Binding] = [:]
        for s in sized.sizes {
            extra[s.name] = s.shortcut.map { .set($0) } ?? .remove
        }
        let overrides = choices.shortcuts.mapValues { sc -> Binding in sc.map { .set($0.input) } ?? .remove }
        let merged = Keymaps.shortcuts(overrides, extra: extra, keymap: Keymap(rawValue: choices.keymap) ?? .rectangle)
        map = merged.map
        sizes = sized.sizes
        problems = sized.problems + merged.problems
    }

    // specs maps each custom size's action name to its spec.
    public var specs: [String: CustomSpec] {
        Dictionary(uniqueKeysWithValues: sizes.map { ($0.name, $0.spec) })
    }
}

// MouseButtons checks mouse button bindings.
public enum MouseButtons {
    // valid returns the bindings in saved whose button is 2 to 31 and whose action is known or one
    // of sizes, keyed by button number, plus the problems found. Buttons 0 and 1 are the primary
    // and secondary buttons and cannot be bound.
    public static func valid(_ saved: [String: String], sizes: Set<String> = []) -> (
        map: [Int: String], problems: [String]
    ) {
        var out: [Int: String] = [:]
        var problems: [String] = []
        for (key, name) in saved.sorted(by: { $0.key < $1.key }) {
            guard let button = Int(key), (2...31).contains(button) else {
                problems.append("mouseButtons has button \(key): use a number from 2 to 31")
                continue
            }
            guard Keymaps.known(name) || sizes.contains(name) else {
                problems.append("mouseButtons names unknown action \(name) for button \(button): ignoring it")
                continue
            }
            out[button] = name
        }
        return (out, problems)
    }
}
