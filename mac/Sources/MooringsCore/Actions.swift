import Foundation

// LastPress records the last action applied to a window, so a repeat press steps its cycle.
public struct LastPress: Equatable, Sendable {
    // name is the action applied.
    public var name: String
    // press is the press count, from 1.
    public var press: Int
    // frame is the window's frame after the action.
    public var frame: Frame

    // init builds a record.
    public init(name: String, press: Int, frame: Frame) {
        self.name = name
        self.press = press
        self.frame = frame
    }
}

// ActionTarget is the screen an action runs on and every screen it may move to.
public struct ActionTarget: Equatable, Sendable {
    // screens are the screens' frames, used to order them left to right.
    public var screens: [Frame]
    // areas are the action areas parallel to screens: the channel on the ultrawide and the usable
    // frame elsewhere.
    public var areas: [Frame]
    // index is the screen the window is on.
    public var index: Int
    // notched lists the screens with a camera notch.
    public var notched: Set<Int>
    // staged lists the screens showing the Stage Manager strip.
    public var staged: Set<Int>
    // stageOnRight reports whether the Stage Manager strip sits on the right, as it does with the
    // Dock on the left.
    public var stageOnRight: Bool

    // init builds a target. Screen 0 is the main screen.
    public init(
        screens: [Frame], areas: [Frame], index: Int, notched: Set<Int> = [], staged: Set<Int> = [],
        stageOnRight: Bool = false
    ) {
        self.screens = screens
        self.areas = areas
        self.index = index
        self.notched = notched
        self.staged = staged
        self.stageOnRight = stageOnRight
    }
}

// Actions picks the frame each window action gives a window.
public enum Actions {
    // step is how many points larger and smaller move each free edge.
    public static let step = 30.0
    // sizePrefix starts the action name of every custom size.
    public static let sizePrefix = "size:"
    // tolerance is how many points a frame may drift and still count as the last action's result.
    public static let tolerance = 2.0

    // specifiedName is the action that sizes a window to the behaviors' specified size, centered.
    public static let specifiedName = "specified"
    // opposites maps each half to the half across from it.
    public static let opposites = [
        "left-half": "right-half", "right-half": "left-half", "top-half": "bottom-half", "bottom-half": "top-half",
    ]
    // quadrants lists the corners in the order a repeat press steps through them.
    public static let quadrants = ["top-left", "top-right", "bottom-left", "bottom-right"]
    // maximizers lists the actions edge gaps skip when applyGapsToMaximize is off.
    public static let maximizers: Set = ["maximize", "almost-maximize", "maximize-height"]
    // displayNames lists display-one to display-nine, which send a window to that screen in order.
    public static let displayNames = [
        "display-one", "display-two", "display-three", "display-four", "display-five",
        "display-six", "display-seven", "display-eight", "display-nine",
    ]

    // near reports whether two frames match within tolerance.
    public static func near(_ a: Frame, _ b: Frame, tolerance: Double = tolerance) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance
    }

    // order returns screen indexes in display order. yThenMinX puts a row of screens above another
    // first and orders each row left to right, minX orders by left edge then top, and midX orders by
    // center.
    public static func order(_ screens: [Frame], by ordering: ScreenOrdering = .yThenMinX) -> [Int] {
        screens.indices.sorted { a, b in
            let s = screens[a], t = screens[b]
            switch ordering {
            case .midX:
                return s.x + s.w / 2 < t.x + t.w / 2
            case .minX:
                return s.x != t.x ? s.x < t.x : s.y < t.y
            case .yThenMinX:
                if s.y + s.h <= t.y { return true }
                if t.y + t.h <= s.y { return false }
                return s.x != t.x ? s.x < t.x : s.y < t.y
            }
        }
    }

    // neighbor returns the screen dir steps from index in screen order, wrapping.
    public static func neighbor(
        _ screens: [Frame], _ index: Int, _ dir: Int, by ordering: ScreenOrdering = .yThenMinX
    ) -> Int {
        let list = order(screens, by: ordering)
        guard let at = list.firstIndex(of: index) else { return index }
        return list[((at + dir) % list.count + list.count) % list.count]
    }

    // area returns the action area of screen i after the behaviors' edge gaps and Stage Manager
    // strip. The strip is reserved only on an area that reaches the strip's screen edge, so an
    // anchored strip already holding that edge is not shrunk twice.
    public static func area(_ target: ActionTarget, _ i: Int, _ b: Behaviors, maximize: Bool = false) -> Frame {
        let a = target.areas[i]
        let s = target.screens[i]
        let side = target.stageOnRight ? abs(a.x + a.w - (s.x + s.w)) <= tolerance : abs(a.x - s.x) <= tolerance
        var b = b
        if !side {
            b.alwaysAccountForStage = false
        }
        return Behavior.effectiveArea(a, b, isMain: i == 0, isMaximize: maximize, hasNotch: target.notched.contains(i),
                                      stageActive: target.staged.contains(i) && side, stageOnRight: target.stageOnRight)
    }

    // frame returns the frame action name gives a window at cur, the press count for a cycling
    // action, and the action the result counts as for the next press: a traverse or switch to the
    // other side counts as that side's half. It returns a nil frame for a display move with one
    // screen, an unknown custom size, or an unknown name.
    public static func frame(
        _ name: String,
        cur: Frame,
        target: ActionTarget,
        gap: Double = 0,
        sizes: [String: CustomSpec] = [:],
        last: LastPress? = nil,
        behavior: Behaviors = Behaviors()
    ) -> (Frame?, press: Int, name: String) {
        let maximize = maximizers.contains(name)
        let areaOf = { (i: Int) in Self.area(target, i, behavior, maximize: maximize) }
        let ordering = behavior.screensOrderedByX
        if name == "next-display" || name == "previous-display" {
            let to = neighbor(target.screens, target.index, name == "next-display" ? 1 : -1, by: ordering)
            if to == target.index {
                return (nil, 1, name)
            }
            return (Geometry.transfer(cur, from: areaOf(target.index), to: areaOf(to)), 1, name)
        }
        let list = order(target.screens, by: ordering)
        if let n = displayNames.firstIndex(of: name) {
            guard n < list.count, list[n] != target.index else { return (nil, 1, name) }
            return (Geometry.transfer(cur, from: areaOf(target.index), to: areaOf(list[n])), 1, name)
        }
        let area = areaOf(target.index)
        if name == specifiedName {
            let spec = CustomSpec(width: behavior.specifiedWidth, height: behavior.specifiedHeight)
            return (Geometry.custom(area, spec, gap: gap), 1, name)
        }
        if name == "larger" || name == "smaller" {
            return (Geometry.resize(area, cur, name == "larger" ? step : -step, gap: gap), 1, name)
        }
        if name.hasPrefix(sizePrefix) {
            return (sizes[name].map { Geometry.custom(area, $0, gap: gap) }, 1, name)
        }
        var press = 1
        if let last, last.name == name, near(cur, last.frame) {
            press = last.press + 1
        }
        let direction = name == "left-half" ? -1 : name == "right-half" ? 1 : 0
        let outcome = Behavior.repeatOutcome(
            behavior.subsequentExecution, press: press, displayIndex: list.firstIndex(of: target.index) ?? 0,
            displayCount: list.count, direction: direction, half: opposites[name] != nil,
            corner: quadrants.contains(name))
        switch outcome {
        case .place:
            return (Geometry.cycle(name, 1, area, cur, gap: gap), 1, name)
        case .cycleSize:
            return (Geometry.cycle(name, press, area, cur, gap: gap), press, name)
        case let .moveToDisplay(i):
            let there = areaOf(list[i])
            if behavior.subsequentExecution != .cycleDisplays, let other = opposites[name] {
                return (Geometry.cycle(other, 1, there, cur, gap: gap), 1, other)
            }
            return (Geometry.cycle(name, 1, there, cur, gap: gap), press, name)
        case .cycleQuadrant:
            let start = quadrants.firstIndex(of: name) ?? 0
            return (Geometry.position(quadrants[(start + press - 1) % quadrants.count], area, cur, gap: gap), press, name)
        case .switchSide:
            let other = opposites[name] ?? name
            return (Geometry.cycle(other, 1, area, cur, gap: gap), 1, other)
        }
    }
}
