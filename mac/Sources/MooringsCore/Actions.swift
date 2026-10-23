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

    // init builds a target.
    public init(screens: [Frame], areas: [Frame], index: Int) {
        self.screens = screens
        self.areas = areas
        self.index = index
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

    // near reports whether two frames match within tolerance.
    public static func near(_ a: Frame, _ b: Frame, tolerance: Double = tolerance) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance
    }

    // order returns screen indexes left to right, then top to bottom.
    public static func order(_ screens: [Frame]) -> [Int] {
        screens.indices.sorted { a, b in
            screens[a].x != screens[b].x ? screens[a].x < screens[b].x : screens[a].y < screens[b].y
        }
    }

    // neighbor returns the screen dir steps from index in screen order, wrapping.
    public static func neighbor(_ screens: [Frame], _ index: Int, _ dir: Int) -> Int {
        let list = order(screens)
        guard let at = list.firstIndex(of: index) else { return index }
        return list[((at + dir) % list.count + list.count) % list.count]
    }

    // frame returns the frame action name gives a window at cur, and the press count for a cycling
    // action. It returns nil for a display move with one screen, an unknown custom size, or an
    // unknown name.
    public static func frame(
        _ name: String,
        cur: Frame,
        target: ActionTarget,
        gap: Double = 0,
        sizes: [String: CustomSpec] = [:],
        last: LastPress? = nil
    ) -> (Frame?, press: Int) {
        if name == "next-display" || name == "previous-display" {
            let to = neighbor(target.screens, target.index, name == "next-display" ? 1 : -1)
            if to == target.index {
                return (nil, 1)
            }
            return (Geometry.transfer(cur, from: target.areas[target.index], to: target.areas[to]), 1)
        }
        let area = target.areas[target.index]
        if name == "larger" || name == "smaller" {
            return (Geometry.resize(area, cur, name == "larger" ? step : -step, gap: gap), 1)
        }
        if name.hasPrefix(sizePrefix) {
            return (sizes[name].map { Geometry.custom(area, $0, gap: gap) }, 1)
        }
        var press = 1
        if let last, last.name == name, near(cur, last.frame) {
            press = last.press + 1
        }
        return (Geometry.cycle(name, press, area, cur, gap: gap), press)
    }
}
