import Foundation

// SubsequentExecution names what pressing the same shortcut again does.
public enum SubsequentExecution: String, CaseIterable, Codable, Sendable {
    case cycleSizes = "cycle-sizes"
    case traverseDisplays = "traverse-displays"
    case none
    case traverseAndCycle = "traverse-and-cycle"
    case cycleDisplays = "cycle-displays"
    // cycleQuadrants is Rectangle's resizeAndCycleQuadrants: corners step through the four
    // quadrants and every other action cycles sizes.
    case cycleQuadrants = "cycle-quadrants"
    case switchSides = "switch-sides"
}

// EnhancedUIMode names how moorings treats an app's Enhanced UI while it moves a window.
public enum EnhancedUIMode: String, CaseIterable, Codable, Sendable {
    case disableEnable = "disable-enable"
    case disableOnly = "disable-only"
    case frontmostDisable = "frontmost-disable"
    case automatic
}

// ScreenOrdering names how displays are ordered when an action steps to the next or previous one.
public enum ScreenOrdering: String, CaseIterable, Codable, Sendable {
    case midX = "mid-x"
    case minX = "min-x"
    case yThenMinX = "y-then-min-x"
}

// Behaviors holds the window action behavior choices, each at Rectangle's default.
public struct Behaviors: Equatable, Sendable, Codable {
    // subsequentExecution is what a repeated shortcut does.
    public var subsequentExecution: SubsequentExecution = .cycleSizes
    // repeatedMaximizeRestores reports whether maximize pressed again restores the previous size.
    public var repeatedMaximizeRestores: Bool = false
    // centerHalfCycles reports whether the center half action cycles on repeat.
    public var centerHalfCycles: Bool = false
    // halvesPreserveOtherAxis reports whether a half action keeps the window's size on the other axis.
    public var halvesPreserveOtherAxis: Bool = false
    // minimumWindowWidth is the smallest width fraction of the area a window shrinks to.
    public var minimumWindowWidth: Double = 0.25
    // minimumWindowHeight is the smallest height fraction of the area a window shrinks to.
    public var minimumWindowHeight: Double = 0.25
    // screenEdgeGapTop is the gap in points kept at the top screen edge.
    public var screenEdgeGapTop: Double = 0
    // screenEdgeGapBottom is the gap in points kept at the bottom screen edge.
    public var screenEdgeGapBottom: Double = 0
    // screenEdgeGapLeft is the gap in points kept at the left screen edge.
    public var screenEdgeGapLeft: Double = 0
    // screenEdgeGapRight is the gap in points kept at the right screen edge.
    public var screenEdgeGapRight: Double = 0
    // screenEdgeGapTopNotch is the top gap used on a display with a notch, negative to use the top gap.
    public var screenEdgeGapTopNotch: Double = -1
    // gapsOnMainOnly reports whether edge gaps apply to the main display only.
    public var gapsOnMainOnly: Bool = false
    // applyGapsToMaximize reports whether edge gaps apply to maximize.
    public var applyGapsToMaximize: Bool = true
    // unsnapRestore reports whether dragging a snapped window restores its size from before the snap.
    public var unsnapRestore: Bool = true
    // doubleClickTitleBar reports whether double-clicking a title bar maximizes or restores the window.
    public var doubleClickTitleBar: Bool = false
    // doubleClickIgnoredApps lists the apps whose title bars are left alone.
    public var doubleClickIgnoredApps: [String] = []
    // moveCursor reports whether the cursor follows a window moved by a shortcut.
    public var moveCursor: Bool = false
    // enhancedUI is how an app's Enhanced UI is handled while a window moves.
    public var enhancedUI: EnhancedUIMode = .automatic
    // stageSize is the width in points Stage Manager reserves on its side of the screen.
    public var stageSize: Double = 190
    // alwaysAccountForStage reports whether the Stage Manager strip is reserved even when it is off.
    public var alwaysAccountForStage: Bool = false
    // hideMenuBarIcon reports whether the menu bar icon is hidden.
    public var hideMenuBarIcon: Bool = false
    // screensOrderedByX is how displays are ordered for next and previous display actions.
    public var screensOrderedByX: ScreenOrdering = .yThenMinX
    // specifiedWidth is the width in points of the specified size action.
    public var specifiedWidth: Double = 1680
    // specifiedHeight is the height in points of the specified size action.
    public var specifiedHeight: Double = 1050
    // animate reports whether shortcut, menu and link moves slide the window instead of jumping. It is
    // experimental and off by default.
    public var animate: Bool = false

    // init builds behaviors at their defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case subsequentExecution, repeatedMaximizeRestores, centerHalfCycles, halvesPreserveOtherAxis
        case minimumWindowWidth, minimumWindowHeight, screenEdgeGapTop, screenEdgeGapBottom, screenEdgeGapLeft
        case screenEdgeGapRight, screenEdgeGapTopNotch, gapsOnMainOnly, applyGapsToMaximize, unsnapRestore
        case doubleClickTitleBar, doubleClickIgnoredApps, moveCursor, enhancedUI, stageSize
        case alwaysAccountForStage, hideMenuBarIcon, screensOrderedByX, specifiedWidth, specifiedHeight, animate
    }

    // init decodes saved behaviors, keeping the default for anything missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subsequentExecution =
            (try? c.decodeIfPresent(SubsequentExecution.self, forKey: .subsequentExecution))
            ?? .cycleSizes
        repeatedMaximizeRestores = (try? c.decodeIfPresent(Bool.self, forKey: .repeatedMaximizeRestores)) ?? false
        centerHalfCycles = (try? c.decodeIfPresent(Bool.self, forKey: .centerHalfCycles)) ?? false
        halvesPreserveOtherAxis = (try? c.decodeIfPresent(Bool.self, forKey: .halvesPreserveOtherAxis)) ?? false
        minimumWindowWidth = (try? c.decodeIfPresent(Double.self, forKey: .minimumWindowWidth)) ?? 0.25
        minimumWindowHeight = (try? c.decodeIfPresent(Double.self, forKey: .minimumWindowHeight)) ?? 0.25
        screenEdgeGapTop = (try? c.decodeIfPresent(Double.self, forKey: .screenEdgeGapTop)) ?? 0
        screenEdgeGapBottom = (try? c.decodeIfPresent(Double.self, forKey: .screenEdgeGapBottom)) ?? 0
        screenEdgeGapLeft = (try? c.decodeIfPresent(Double.self, forKey: .screenEdgeGapLeft)) ?? 0
        screenEdgeGapRight = (try? c.decodeIfPresent(Double.self, forKey: .screenEdgeGapRight)) ?? 0
        screenEdgeGapTopNotch = (try? c.decodeIfPresent(Double.self, forKey: .screenEdgeGapTopNotch)) ?? -1
        gapsOnMainOnly = (try? c.decodeIfPresent(Bool.self, forKey: .gapsOnMainOnly)) ?? false
        applyGapsToMaximize = (try? c.decodeIfPresent(Bool.self, forKey: .applyGapsToMaximize)) ?? true
        unsnapRestore = (try? c.decodeIfPresent(Bool.self, forKey: .unsnapRestore)) ?? true
        doubleClickTitleBar = (try? c.decodeIfPresent(Bool.self, forKey: .doubleClickTitleBar)) ?? false
        doubleClickIgnoredApps = (try? c.decodeIfPresent([String].self, forKey: .doubleClickIgnoredApps)) ?? []
        moveCursor = (try? c.decodeIfPresent(Bool.self, forKey: .moveCursor)) ?? false
        enhancedUI = (try? c.decodeIfPresent(EnhancedUIMode.self, forKey: .enhancedUI)) ?? .automatic
        stageSize = (try? c.decodeIfPresent(Double.self, forKey: .stageSize)) ?? 190
        alwaysAccountForStage = (try? c.decodeIfPresent(Bool.self, forKey: .alwaysAccountForStage)) ?? false
        hideMenuBarIcon = (try? c.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon)) ?? false
        screensOrderedByX = (try? c.decodeIfPresent(ScreenOrdering.self, forKey: .screensOrderedByX)) ?? .yThenMinX
        specifiedWidth = (try? c.decodeIfPresent(Double.self, forKey: .specifiedWidth)) ?? 1680
        specifiedHeight = (try? c.decodeIfPresent(Double.self, forKey: .specifiedHeight)) ?? 1050
        animate = (try? c.decodeIfPresent(Bool.self, forKey: .animate)) ?? false
    }
}

// RepeatOutcome is what a repeated shortcut should do.
public enum RepeatOutcome: Equatable, Sendable {
    // place puts the window in the action's first position.
    case place
    // cycleSize steps to the action's next size.
    case cycleSize
    // moveToDisplay moves the window to the display at the index.
    case moveToDisplay(Int)
    // cycleQuadrant steps a corner action to its next position.
    case cycleQuadrant
    // switchSide moves a half action to the opposite side.
    case switchSide
}

// Behavior holds the pure decisions the behavior choices drive.
public enum Behavior {
    // effectiveArea returns the area after the edge gaps and the Stage Manager reservation. The stage
    // strip sits on the left unless stageOnRight, and is reserved when active or always accounted for.
    public static func effectiveArea(
        _ area: Frame, _ b: Behaviors, isMain: Bool = true, isMaximize: Bool = false, hasNotch: Bool = false,
        stageActive: Bool = false, stageOnRight: Bool = false
    ) -> Frame {
        var out = area
        if stageActive || b.alwaysAccountForStage {
            out.w -= b.stageSize
            if !stageOnRight { out.x += b.stageSize }
        }
        if (b.gapsOnMainOnly && !isMain) || (isMaximize && !b.applyGapsToMaximize) { return out }
        let top = hasNotch && b.screenEdgeGapTopNotch >= 0 ? b.screenEdgeGapTopNotch : b.screenEdgeGapTop
        out.x += b.screenEdgeGapLeft
        out.y += top
        out.w -= b.screenEdgeGapLeft + b.screenEdgeGapRight
        out.h -= top + b.screenEdgeGapBottom
        return out
    }

    // repeatOutcome decides what a shortcut does from its press count, the display it is on and the
    // display count. direction is -1 or 1 for a left or right half, 0 otherwise, half marks any half
    // action, and corner marks a corner action. Traverse wraps around the displays, and traverse and
    // cycle cycles sizes instead of wrapping or on one display, as Rectangle does.
    public static func repeatOutcome(
        _ mode: SubsequentExecution, press: Int, displayIndex: Int, displayCount: Int, direction: Int = 0,
        half: Bool = false, corner: Bool = false
    ) -> RepeatOutcome {
        guard press > 1 else { return .place }
        let n = max(displayCount, 1)
        let step = displayIndex + direction
        let next = (step % n + n) % n
        let sideways = direction != 0 && displayCount > 1
        switch mode {
        case .none: return .place
        case .cycleSizes: return .cycleSize
        case .traverseDisplays: return sideways ? .moveToDisplay(next) : .place
        case .traverseAndCycle: return sideways && step == next ? .moveToDisplay(next) : .cycleSize
        case .cycleDisplays: return displayCount > 1 ? .moveToDisplay((displayIndex + 1) % displayCount) : .place
        case .cycleQuadrants: return corner ? .cycleQuadrant : .cycleSize
        case .switchSides: return direction != 0 || half ? .switchSide : .place
        }
    }

    // animationWrites is how many frame writes a window move animation makes, the last one exact.
    public static let animationWrites = 9

    // animationTime is how long a window move animation takes, in seconds.
    public static let animationTime = 0.15

    // steps returns the frames a window passes through sliding from start to target, eased out, starting
    // with start and ending exactly on target, with writes frames after start.
    public static func steps(from start: Frame, to target: Frame, writes: Int = animationWrites) -> [Frame] {
        let n = max(writes, 1)
        return [start]
            + (1...n).map { i in
                if i == n { return target }
                let t = Double(i) / Double(n)
                let e = 1 - pow(1 - t, 3)
                func mix(_ a: Double, _ b: Double) -> Double { (a + (b - a) * e).rounded() }
                return Frame(
                    x: mix(start.x, target.x), y: mix(start.y, target.y), w: mix(start.w, target.w),
                    h: mix(start.h, target.h))
            }
    }

    // centerCycle lists the positions center half steps through on repeat when centerHalfCycles is on.
    public static let centerCycle = ["center-half", "center-two-thirds", "center-third"]

    // keepOtherAxis returns f with cur's span on the axis a half does not set: y and height for the
    // left and right halves, x and width for the top and bottom halves, kept inside area. Any other
    // action returns f unchanged.
    public static func keepOtherAxis(_ name: String, _ f: Frame, cur: Frame, area: Frame) -> Frame {
        var out = f
        switch Geometry.aliases[name] ?? name {
        case "left-half", "right-half":
            out.h = min(cur.h, area.h)
            out.y = max(area.y, min(cur.y, area.y + area.h - out.h))
        case "top-half", "bottom-half":
            out.w = min(cur.w, area.w)
            out.x = max(area.x, min(cur.x, area.x + area.w - out.w))
        default:
            break
        }
        return out
    }

    // restoresMaximize reports whether a maximize press restores the window instead: the choice is on
    // and the window still sits where the last maximize press put it.
    public static func restoresMaximize(_ name: String, cur: Frame, last: LastPress?, _ b: Behaviors) -> Bool {
        guard b.repeatedMaximizeRestores, name == "maximize", let last, last.name == "maximize" else { return false }
        return Actions.near(cur, last.frame)
    }

    // chromiumBrowsers lists the bundle id families of the Chromium browsers, whose Enhanced UI is
    // left off because turning it back on slows them.
    public static let chromiumBrowsers = [
        "com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper", "com.operasoftware.OperaNightly", "com.operasoftware.OperaGX",
        "com.operasoftware.OperaGXNext", "com.operasoftware.OperaGXDeveloper", "com.operasoftware.OperaGXNightly",
        "company.thebrowser.Browser", "company.thebrowser.dia", "ai.perplexity.comet", "com.openai.atlas",
    ]

    // chromium reports whether bundle is a Chromium browser or one of its channels.
    public static func chromium(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        return chromiumBrowsers.contains { bundle == $0 || bundle.hasPrefix($0 + ".") }
    }

    // restoresEnhancedUI reports whether an app's Enhanced UI, turned off for a move, is turned back on
    // after it. assistive reports whether VoiceOver is on.
    public static func restoresEnhancedUI(_ mode: EnhancedUIMode, bundle: String?, assistive: Bool) -> Bool {
        switch mode {
        case .disableEnable: return true
        case .disableOnly, .frontmostDisable: return false
        case .automatic: return assistive || !chromium(bundle)
        }
    }

    // disablesEnhancedUIOnActivation reports whether an app's Enhanced UI is turned off when it comes to
    // the front.
    public static func disablesEnhancedUIOnActivation(_ mode: EnhancedUIMode, bundle: String?, assistive: Bool) -> Bool
    {
        switch mode {
        case .frontmostDisable: return true
        case .automatic: return !assistive && chromium(bundle)
        case .disableEnable, .disableOnly: return false
        }
    }

    // unsnapSize returns the size to restore when a snapped window is dragged away, or nil to leave it.
    public static func unsnapSize(
        _ b: Behaviors, wasSnapped: Bool, saved: (w: Double, h: Double)?, current: Frame
    ) -> (w: Double, h: Double)? {
        guard b.unsnapRestore, wasSnapped, let saved, saved.w != current.w || saved.h != current.h else {
            return nil
        }
        return saved
    }

    // snapped reports whether a window first read at start, after the cursor moved moved points from
    // where the button went down, still sat at placed, the frame its last action gave it.
    public static func snapped(_ placed: Frame, start: Frame, moved: Double) -> Bool {
        let t = Actions.tolerance
        return abs(placed.w - start.w) <= t && abs(placed.h - start.h) <= t
            && abs(placed.x - start.x) + abs(placed.y - start.y) <= moved + t
    }

    // stillReads is how many reads must find a dragged window still before the drag is taken as not
    // moving a window.
    public static let stillReads = 3
    // stillSeconds is how long after the first still read a window may still start moving.
    // Accessibility reports a dragged window's position 100 ms or more behind the screen.
    public static let stillSeconds = 0.5

    // stillDrag reports whether a drag has stopped being a window drag: reads reads found the window
    // still and the first of them was seconds ago.
    public static func stillDrag(reads: Int, seconds: Double) -> Bool {
        reads >= stillReads && seconds >= stillSeconds
    }

    // unsnapFrame returns the frame of a window at current resized to size. The top left stays put
    // unless the cursor, grab points from the left edge, would fall off the narrower window. Then it
    // shifts right only as far as keeps the cursor over the window, as Rectangle does.
    public static func unsnapFrame(_ current: Frame, size: (w: Double, h: Double), grab: Double) -> Frame {
        let inset = min(32, size.w / 2)
        let shift = min(max(0, grab - (size.w - inset)), max(0, current.w - size.w))
        return Frame(x: current.x + shift, y: current.y, w: size.w, h: size.h)
    }

    // titleBarRoles lists the roles of the elements a title bar double-click may land on, as Rectangle
    // allows. Buttons, fields and tabs keep their own double-click.
    public static let titleBarRoles: Set<String> = ["AXWindow", "AXToolbar", "AXGroup", "AXTabGroup", "AXStaticText"]

    // onTitleBar reports whether a click at p lands on the title bar of a window at frame with its
    // green button at button, on an element with role. The title bar runs from the top of the window
    // down as far below the button's middle as the middle sits below the top, right of the button.
    public static func onTitleBar(_ p: Point, window: Frame, button: Frame?, role: String?) -> Bool {
        guard let button, let role, titleBarRoles.contains(role) else { return false }
        let band = 2 * (button.y + button.h / 2 - window.y)
        return p.y >= window.y && p.y < window.y + band && p.x >= button.x + button.w && p.x < window.x + window.w
    }

    // titleBarAction returns the action a title bar double-click runs on a window at frame: restore
    // when the window still sits where its last maximize put it, maximize otherwise.
    public static func titleBarAction(last: LastPress?, frame: Frame) -> String {
        if let last, last.name == "maximize", Actions.near(last.frame, frame) {
            return "restore"
        }
        return "maximize"
    }
}

// WindowButton names a title bar button whose click a binding can take over.
public enum WindowButton: String, CaseIterable, Sendable {
    // red is the close button.
    case red
    // yellow is the minimize button.
    case yellow
    // green is the zoom and full screen button.
    case green

    // init reads the button from an element's accessibility subrole, or returns nil for anything else.
    public init?(subrole: String?) {
        switch subrole {
        case "AXCloseButton": self = .red
        case "AXMinimizeButton": self = .yellow
        case "AXZoomButton", "AXFullScreenButton": self = .green
        default: return nil
        }
    }
}

// ButtonClicks resolves clicks on the title bar buttons to the actions bound to them. A binding is
// saved under the button's name, with "+" and a modifier when one is held, such as red+option.
public enum ButtonClicks {
    // modifiers lists the modifiers a binding can take, with "" for a plain click, in menu order.
    public static let modifiers = ["", "shift", "option", "command"]
    // cornerWidth is how far right of a window's left edge, in points, the title bar buttons reach.
    public static let cornerWidth = 100.0
    // cornerHeight is how far below a window's top, in points, the title bar buttons reach, with a
    // tall toolbar.
    public static let cornerHeight = 60.0

    // key returns the saved key of button clicked with modifier.
    public static func key(_ button: WindowButton, _ modifier: String) -> String {
        modifier.isEmpty ? button.rawValue : button.rawValue + "+" + modifier
    }

    // modifier returns the modifier of a click, "" for none, or nil when Control or more than one
    // modifier is held, which no binding takes.
    public static func modifier(shift: Bool, option: Bool, command: Bool, control: Bool) -> String? {
        let held = [(shift, "shift"), (option, "option"), (command, "command")].filter(\.0).map(\.1)
        guard !control, held.count <= 1 else { return nil }
        return held.first ?? ""
    }

    // bound reports whether any binding takes a click with modifier, so a click no binding takes
    // skips the button lookup.
    public static func bound(_ clicks: [String: String], modifier: String) -> Bool {
        WindowButton.allCases.contains { clicks[key($0, modifier)] != nil }
    }

    // action returns the action bound to button clicked with modifier, or nil when none is bound or
    // the bound action is not known and not one of sizes.
    public static func action(
        _ clicks: [String: String], _ button: WindowButton, _ modifier: String, sizes: Set<String> = []
    ) -> String? {
        guard let name = clicks[key(button, modifier)], Keymaps.known(name) || sizes.contains(name) else { return nil }
        return name
    }

    // near reports whether p sits in the top left corner of a window at frame, where the title bar
    // buttons are.
    public static func near(_ p: Point, _ frame: Frame) -> Bool {
        p.x >= frame.x && p.x < frame.x + min(cornerWidth, frame.w)
            && p.y >= frame.y && p.y < frame.y + min(cornerHeight, frame.h)
    }

    // valid returns the problems in saved: a key that names no button and modifier, or an action that
    // is not known and not one of sizes.
    public static func valid(_ saved: [String: String], sizes: Set<String> = []) -> [String] {
        let keys = Set(WindowButton.allCases.flatMap { b in modifiers.map { key(b, $0) } })
        return saved.sorted { $0.key < $1.key }.compactMap { k, name in
            if !keys.contains(k) {
                return "buttonClicks has \(k): use red, yellow or green, with +shift, +option or +command"
            }
            if !Keymaps.known(name) && !sizes.contains(name) {
                return "buttonClicks names unknown action \(name) for \(k): ignoring it"
            }
            return nil
        }
    }
}
