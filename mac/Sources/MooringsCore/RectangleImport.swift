import Foundation

// RectangleValue is one decoded Rectangle default. Rectangle exports each default as an object holding
// one of these encodings under its own key.
public enum RectangleValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case float(Float)
    case double(Double)
    case string(String)

    // number returns the value as a Double when it is numeric, or nil for a bool or a string.
    var number: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .float(let v): return Double(v)
        case .double(let v): return v
        case .bool, .string: return nil
        }
    }

    // integer returns the value as an Int when it is an int, or a whole float or double.
    var integer: Int? {
        switch self {
        case .int(let v): return v
        case .float, .double:
            guard let n = number, n == n.rounded(), abs(n) < 1e15 else { return nil }
            return Int(n)
        case .bool, .string: return nil
        }
    }

    // optionalBool decodes Rectangle's three-state bool: 1 is on, 2 is off, and 0 or anything else is
    // unset, which returns nil. A plain bool is accepted too.
    var optionalBool: Bool? {
        if case .bool(let v) = self { return v }
        switch integer {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }
}

// RectangleImportError names why a Rectangle config could not be read.
public enum RectangleImportError: Error, Equatable, Sendable {
    // malformed means the data is not a Rectangle config document.
    case malformed
    // wrongApp means the config was exported by another app. The bundle ID is the one found.
    case wrongApp(String)
}

// RectangleImport reads Rectangle's exported config into moorings choices.
public enum RectangleImport {
    // bundleIds lists the bundle IDs whose exports are accepted.
    public static let bundleIds: Set<String> = ["com.knollsoft.Rectangle", "com.knollsoft.Hookshot"]

    // keyNames maps a Carbon virtual key code (kVK_ value) to the key name Keymaps uses.
    static let keyNames: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
        13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i",
        35: "p", 36: "return", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`", 51: "delete", 53: "escape",
        64: "f17", 79: "f18", 80: "f19", 90: "f20", 96: "f5", 97: "f6", 98: "f7", 99: "f3", 100: "f8",
        101: "f9", 103: "f11", 105: "f13", 106: "f16", 107: "f14", 109: "f10", 111: "f12", 113: "f15",
        115: "home", 116: "pageup", 117: "forwarddelete", 118: "f4", 119: "end", 120: "f2", 121: "pagedown",
        122: "f1", 123: "left", 124: "right", 125: "down", 126: "up",
    ]

    // modifierBits maps each NSEvent modifier flag bit to the moorings modifier it stands for.
    static let modifierBits: [(bit: UInt, modifier: Modifier)] = [
        (1 << 18, .ctrl), (1 << 19, .alt), (1 << 17, .shift), (1 << 20, .cmd),
    ]

    // snapModifierBits maps each NSEvent modifier flag bit to the name SnapChoices.snapModifiers uses.
    static let snapModifierBits: [(bit: Int, name: String)] = [
        (1 << 17, "shift"), (1 << 18, "control"), (1 << 19, "option"), (1 << 20, "command"),
    ]

    // aliases maps the Rectangle action names that differ from moorings beyond kebab-case.
    static let aliases: [String: String] = [
        "leftSide": "left-half", "rightSide": "right-half", "topSide": "top-half", "bottomSide": "bottom-half",
        "centerSection": "center-half",
    ]

    // snapAreaBits maps each ignoredSnapAreas bit to a moorings snap area name.
    static let snapAreaBits: [(bit: Int, name: String)] = [
        (1 << 0, "top"), (1 << 1, "bottom"), (1 << 2, "left"), (1 << 3, "right"),
        (1 << 4, "top-left"), (1 << 5, "top-right"), (1 << 6, "bottom-left"), (1 << 7, "bottom-right"),
    ]

    // Config is the document Rectangle exports.
    private struct Config: Decodable {
        var bundleId: String?
        var shortcuts: [String: Shortcut]?
        var defaults: [String: Coded]?
    }

    // Shortcut is a Rectangle key binding.
    private struct Shortcut: Decodable {
        var keyCode: Int
        var modifierFlags: UInt
    }

    // Coded is Rectangle's CodableDefault: an object with whichever encodings are present.
    private struct Coded: Decodable {
        var bool: Bool?
        var int: Int?
        var float: Float?
        var double: Double?
        var string: String?

        // value returns the one encoding present, or nil when the object is empty.
        var value: RectangleValue? {
            if let bool { return .bool(bool) }
            if let int { return .int(int) }
            if let double { return .double(double) }
            if let float { return .float(float) }
            if let string { return .string(string) }
            return nil
        }
    }

    // apply reads a Rectangle config export and returns the choices with its shortcuts and defaults
    // applied, plus one warning for each entry that could not be carried over. Empty data and an empty
    // object return the choices unchanged. Malformed JSON or another app's bundle ID throws.
    public static func apply(_ data: Data, to choices: Choices) throws -> (Choices, [String]) {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return (choices, [])
        }
        let config: Config
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw RectangleImportError.malformed
        }
        if let id = config.bundleId, !bundleIds.contains(id) {
            throw RectangleImportError.wrongApp(id)
        }
        var shortcuts: [String: (keyCode: Int, modifierFlags: UInt)] = [:]
        for (name, s) in config.shortcuts ?? [:] {
            shortcuts[name] = (s.keyCode, s.modifierFlags)
        }
        var defaults: [String: RectangleValue] = [:]
        var empty: [String] = []
        for (key, coded) in config.defaults ?? [:] {
            if let v = coded.value {
                defaults[key] = v
            } else {
                empty.append(key)
            }
        }
        var (out, warnings) = apply(shortcuts: shortcuts, defaults: defaults, to: choices)
        warnings += empty.sorted().map { "Rectangle default \($0) has no value and was skipped." }
        if config.shortcuts != nil {
            unbindMissing(shortcuts, in: &out)
        }
        return (out, warnings)
    }

    // apply carries already-decoded shortcuts and defaults onto choices, returning the new choices and a
    // warning line for each entry that could not be carried over.
    public static func apply(
        shortcuts: [String: (keyCode: Int, modifierFlags: UInt)], defaults: [String: RectangleValue],
        to choices: Choices
    ) -> (Choices, [String]) {
        var out = choices
        var warnings: [String] = []
        applyShortcuts(shortcuts, to: &out, warnings: &warnings)
        for key in defaults.keys.sorted() {
            if !applyDefault(key, defaults[key]!, to: &out) {
                warnings.append("Rectangle default \(key) has no moorings setting and was skipped.")
            }
        }
        return (out, warnings)
    }

    // unbindMissing removes the keymap shortcut of every action an export leaves unbound. An export
    // lists every bound shortcut, and Rectangle's own import clears the rest, so moorings does too.
    // The live defaults domain only holds shortcuts the user changed, so it must not come through here.
    private static func unbindMissing(_ shortcuts: [String: (keyCode: Int, modifierFlags: UInt)], in c: inout Choices) {
        let bound = Set(shortcuts.compactMap { $0.value.keyCode >= 0 ? actionName($0.key) : nil })
        for name in (Keymap(rawValue: c.keymap) ?? .rectangle).table.keys where !bound.contains(name) {
            c.shortcuts[name] = .some(nil)
        }
    }

    // kebab turns a camelCase Rectangle action name into moorings' kebab-case.
    static func kebab(_ name: String) -> String {
        var out = ""
        for ch in name {
            if ch.isUppercase {
                if !out.isEmpty { out.append("-") }
                out.append(contentsOf: ch.lowercased())
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // actionName returns the moorings action for a Rectangle name, or nil when moorings has none.
    static func actionName(_ rectangle: String) -> String? {
        let name = aliases[rectangle] ?? kebab(rectangle)
        return Keymaps.known(name) ? name : nil
    }

    // applyShortcuts stores each bound, mappable shortcut as an override on choices. A name that is only
    // an alias never replaces the shortcut of its primary name.
    private static func applyShortcuts(
        _ shortcuts: [String: (keyCode: Int, modifierFlags: UInt)], to choices: inout Choices,
        warnings: inout [String]
    ) {
        for rectangle in shortcuts.keys.sorted() {
            let s = shortcuts[rectangle]!
            guard let name = actionName(rectangle) else {
                warnings.append("Rectangle action \(rectangle) has no moorings action and was skipped.")
                continue
            }
            if s.keyCode < 0 { continue }
            guard let key = keyNames[s.keyCode] else {
                warnings.append("Rectangle shortcut for \(rectangle) uses key code \(s.keyCode), which moorings "
                    + "cannot bind, and was skipped.")
                continue
            }
            if aliases[rectangle] != nil, let primary = shortcuts[primaryName(of: name)], primary.keyCode >= 0 {
                continue
            }
            let mods = modifierBits.filter { s.modifierFlags & $0.bit != 0 }.map(\.modifier)
            let sorted = Array(Set(mods)).sorted().map(\.rawValue)
            choices.shortcuts[name] = .some(StoredShortcut(mods: sorted, key: key))
        }
    }

    // primaryName returns the Rectangle spelling of a moorings action name.
    private static func primaryName(of action: String) -> String {
        var out = ""
        var upper = false
        for ch in action {
            if ch == "-" {
                upper = true
            } else if upper {
                out.append(contentsOf: ch.uppercased())
                upper = false
            } else {
                out.append(ch)
            }
        }
        return out
    }

    // applyDefault sets the moorings field for a Rectangle default. It returns false when the key has no
    // field or the value has the wrong type.
    private static func applyDefault(_ key: String, _ v: RectangleValue, to c: inout Choices) -> Bool {
        switch key {
        case "subsequentExecutionMode":
            let modes: [SubsequentExecution] = [
                .cycleSizes, .traverseDisplays, .none, .traverseAndCycle, .cycleDisplays, .cycleQuadrants,
                .switchSides,
            ]
            guard let i = v.integer, modes.indices.contains(i) else { return false }
            c.behavior.subsequentExecution = modes[i]
        case "repeatedMaximizeRestoresPrevious": return set(v, &c.behavior.repeatedMaximizeRestores)
        case "centerHalfCycles": return setOptional(v, &c.behavior.centerHalfCycles)
        case "halvesPreserveOtherAxisSize": return set(v, &c.behavior.halvesPreserveOtherAxis)
        case "minimumWindowWidth": return set(v, &c.behavior.minimumWindowWidth)
        case "minimumWindowHeight": return set(v, &c.behavior.minimumWindowHeight)
        case "screenEdgeGapTop": return set(v, &c.behavior.screenEdgeGapTop)
        case "screenEdgeGapBottom": return set(v, &c.behavior.screenEdgeGapBottom)
        case "screenEdgeGapLeft": return set(v, &c.behavior.screenEdgeGapLeft)
        case "screenEdgeGapRight": return set(v, &c.behavior.screenEdgeGapRight)
        case "screenEdgeGapTopNotch": return set(v, &c.behavior.screenEdgeGapTopNotch)
        case "screenEdgeGapsOnMainScreenOnly": return set(v, &c.behavior.gapsOnMainOnly)
        case "applyGapsToMaximize": return setOptional(v, &c.behavior.applyGapsToMaximize)
        case "unsnapRestore": return setOptional(v, &c.behavior.unsnapRestore)
        case "doubleClickTitleBar":
            guard let i = v.integer else { return false }
            c.behavior.doubleClickTitleBar = i > 0
        case "doubleClickTitleBarIgnoredApps":
            guard let apps = strings(v) else { return false }
            c.behavior.doubleClickIgnoredApps = apps
        case "moveCursor": return setOptional(v, &c.behavior.moveCursor)
        case "enhancedUI":
            let modes: [EnhancedUIMode] = [.disableEnable, .disableOnly, .frontmostDisable, .automatic]
            guard let i = v.integer, i >= 1, i <= modes.count else { return false }
            c.behavior.enhancedUI = modes[i - 1]
        case "stageSize": return set(v, &c.behavior.stageSize)
        case "alwaysAccountForStage": return setOptional(v, &c.behavior.alwaysAccountForStage)
        case "hideMenubarIcon": return set(v, &c.behavior.hideMenuBarIcon)
        case "screensOrderedByX":
            let modes: [ScreenOrdering] = [.midX, .minX, .yThenMinX]
            guard let i = v.integer, i >= 1, i <= modes.count else { return false }
            c.behavior.screensOrderedByX = modes[i - 1]
        case "specifiedWidth": return set(v, &c.behavior.specifiedWidth)
        case "specifiedHeight": return set(v, &c.behavior.specifiedHeight)
        case "disabledApps":
            guard let apps = strings(v) else { return false }
            for app in apps.sorted() where !c.ignores.contains(app) { c.ignores.append(app) }
        case "gapSize": return set(v, &c.gapPx)
        case "alternateDefaultShortcuts":
            guard case .bool(let recommended) = v else { return false }
            c.keymap = (recommended ? Keymap.rectangle : Keymap.spectacle).rawValue
        case "windowSnapping":
            guard let on = v.optionalBool else { return true }
            c.snap = on
        default: return applySnapping(key, v, to: &c)
        }
        return true
    }

    // applySnapping handles the snap, footprint and stack defaults.
    private static func applySnapping(_ key: String, _ v: RectangleValue, to c: inout Choices) -> Bool {
        switch key {
        case "snapBeforeReachingEdges": return set(v, &c.snapping.snapBeforeReachingEdges)
        case "snapEdgeMarginTop": return set(v, &c.snapping.edgeMarginTop)
        case "snapEdgeMarginBottom": return set(v, &c.snapping.edgeMarginBottom)
        case "snapEdgeMarginLeft": return set(v, &c.snapping.edgeMarginLeft)
        case "snapEdgeMarginRight": return set(v, &c.snapping.edgeMarginRight)
        case "cornerSnapAreaSize": return set(v, &c.snapping.cornerSize)
        case "shortEdgeSnapAreaSize": return set(v, &c.snapping.shortEdgeSize)
        case "ignoredSnapAreas":
            guard let bits = v.integer else { return false }
            c.snapping.ignoredSnapAreas = snapAreaBits.filter { bits & $0.bit != 0 }.map(\.name)
        case "snapModifiers":
            guard let bits = v.integer else { return false }
            c.snapping.snapModifiers = snapModifierBits.filter { bits & $0.bit != 0 }.map(\.name)
        case "footprintAlpha": return set(v, &c.snapping.footprint.alpha)
        case "footprintBorderWidth": return set(v, &c.snapping.footprint.borderWidth)
        case "footprintFade": return setOptional(v, &c.snapping.footprint.fade)
        case "footprintAnimationDurationMultiplier": return set(v, &c.snapping.footprint.animationSpeed)
        case "hapticFeedbackOnSnap": return setOptional(v, &c.snapping.footprint.haptic)
        case "footprintColor":
            guard case .string(let json) = v, let hex = hexColor(json) else { return false }
            c.snapping.footprint.color = hex
        case "cyclingOverlapOffset": return setOptional(v, &c.stacking.overlapOffset)
        case "cyclingOverlapOffsetSize": return set(v, &c.stacking.overlapOffsetSize)
        case "cyclingOverlapMaxCascade":
            guard let i = v.integer else { return false }
            c.stacking.overlapMaxCascade = i
        case "stackBadge": return setOptional(v, &c.stacking.badge)
        case "stackSameSizeOnly": return setOptional(v, &c.stacking.sameSizeOnly)
        default: return false
        }
        return true
    }

    // set stores a plain bool and reports whether the value was one.
    private static func set(_ v: RectangleValue, _ field: inout Bool) -> Bool {
        guard case .bool(let b) = v else { return false }
        field = b
        return true
    }

    // set stores a number and reports whether the value was numeric.
    private static func set(_ v: RectangleValue, _ field: inout Double) -> Bool {
        guard let n = v.number else { return false }
        field = n
        return true
    }

    // setOptional stores a three-state bool. An unset value leaves the field alone and still counts as read.
    private static func setOptional(_ v: RectangleValue, _ field: inout Bool) -> Bool {
        switch v {
        case .bool, .int: break
        default: return false
        }
        if let on = v.optionalBool { field = on }
        return true
    }

    // strings decodes a JSON-encoded string array, or nil when the value is not one.
    private static func strings(_ v: RectangleValue) -> [String]? {
        guard case .string(let json) = v, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    // hexColor turns Rectangle's JSON color (red, green, blue as 0 to 1) into #RRGGBB, or nil.
    private static func hexColor(_ json: String) -> String? {
        struct Color: Decodable { var red: Double; var green: Double; var blue: Double }
        guard let data = json.data(using: .utf8), let c = try? JSONDecoder().decode(Color.self, from: data) else {
            return nil
        }
        func byte(_ x: Double) -> Int { Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
    }
}
