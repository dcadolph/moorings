import MooringsCore

// DragPanelHook is the snap panel a platform may show while a window is dragged.
public protocol DragPanelHook: AnyObject {
    // zone follows the pointer at p over the panel and returns the panel action under it, nil when
    // the panel is off or the pointer is over no target.
    func zone(at p: Point, window: WindowInfo, held: Set<String>, option: Bool) -> String?
    // reset hides the panel at the end of a drag.
    func reset()
}

// StashHook is how a platform stashes a window a Command-drag drops at a screen edge.
public struct StashHook {
    // edge returns the screen edge a drop at a point with the held keys would stash at, nil for none.
    public var edge: (Point, Set<String>) -> StashEdge?
    // stash parks the window at the edge, to come back to the frame the drag began at.
    public var stash: (WindowInfo, StashEdge, Frame?) -> Void

    // init builds the hook from its two parts.
    public init(edge: @escaping (Point, Set<String>) -> StashEdge?, stash: @escaping (WindowInfo, StashEdge, Frame?) -> Void) {
        self.edge = edge
        self.stash = stash
    }
}

// DragFollower follows a window dragged by its frame. While the window moves, the zone or slot
// under the pointer shows as a footprint; on the drop the zone's action runs, or with option held
// over an ultrawide strip the window's app is anchored there. It reads the window at most once per
// travel points, and the adapters call it outside their event callbacks.
public final class DragFollower {
    // travel is how many points the pointer must move between reads of the dragged window.
    public static let travel = 8.0
    // sizeTolerance is how far in points a frame's size may wander and still count as held, since a
    // platform can round a moving window's size by a pixel.
    public static let sizeTolerance = 1.0

    // preview returns the frame an action gives a window on the screen at an index, without moving it.
    public var preview: (String, WindowInfo, Screens, Int) -> Frame?
    // apply runs an action on a window on the screen at an index.
    public var apply: (String, WindowInfo, Screens, Int?) -> Void
    // placed returns the frame the window's last action gave it, nil when none did.
    public var placed: (WindowID) -> Frame? = { _ in nil }
    // unsnap gives a dragged window back its size from before a snap, at its frame, with the pointer
    // the given points from its left edge kept over it.
    public var unsnap: (WindowInfo, Frame, Double) -> Void = { _, _, _ in }
    // appName returns the name to show for a bundle.
    public var appName: (String) -> String = { $0 }
    // changed runs after a drop changed the choices, to save them and wake the passes.
    public var changed: () -> Void = {}
    // stash stashes a Command-drag dropped at an edge, nil where the platform has no stash.
    public var stash: StashHook?
    // panel is the snap panel, nil where the platform has none.
    public var panel: DragPanelHook?
    // showed is told each footprint shown for a new zone and its style.
    public var showed: (Frame, FootprintStyle) -> Void = { _, _ in }
    // dropped is told the window and what it dropped on at the end of each drag that moved a window.
    public var dropped: (WindowID, SnapDrop?) -> Void = { _, _ in }

    // platform reads the windows and screens and shows the footprint and messages.
    private let platform: Platform
    // anchors holds the choices, the slots and the pins.
    private let anchors: Anchors
    // down reports whether a drag that may snap is under way.
    private var down = false
    // done reports whether this drag will not snap.
    private var done = false
    // given is the window the platform said is dragged, nil when the follower must find it.
    private var given: WindowID?
    // win is the dragged window, nil until the first read.
    private var win: WindowInfo?
    // start is the dragged window's frame at the first read.
    private var start: Frame?
    // checks counts the reads that found the window still.
    private var checks = 0
    // firstRead is when a read first found the dragged window still, nil before.
    private var firstRead: Double?
    // moving is true for a drag that moves the window, false for one that sizes it, and nil until
    // the platform's answer or a read decides.
    private var moving: Bool?
    // from is where the pointer was at the last read.
    private var from: Point?
    // drop is the zone or slot under the pointer.
    public private(set) var drop: SnapDrop?
    // screen is the index of the screen the drop is on.
    private var screen: Int?
    // at is where the button went down, nil when the platform did not say.
    private var at: Point?
    // placedFrame is the frame the dragged window's last action gave it, nil unless the window still
    // sat there when the drag began.
    private var placedFrame: Frame?
    // stashAt is the edge a Command-drag would stash the window at, nil when it would not.
    private var stashAt: StashEdge?

    // init builds a follower on platform and anchors that previews and applies actions through the
    // given closures.
    public init(
        platform: Platform, anchors: Anchors, preview: @escaping (String, WindowInfo, Screens, Int) -> Frame?,
        apply: @escaping (String, WindowInfo, Screens, Int?) -> Void
    ) {
        self.platform = platform
        self.anchors = anchors
        self.preview = preview
        self.apply = apply
    }

    // began starts following a drag. window is the dragged window when the platform knows it and
    // moving its answer to move versus size when it has one; at is where the button went down.
    public func began(window: WindowID? = nil, moving: Bool? = nil, at: Point? = nil) {
        reset()
        down = true
        given = window
        self.moving = moving
        self.at = at
        if moving == false {
            done = true
        } else if window != nil, !anchors.choices.paused {
            look()
        }
    }

    // moved follows the pointer at p with the held modifier names, and moves the footprint when the
    // zone changes.
    public func moved(_ p: Point, held: Set<String>) {
        let option = held.contains("option")
        let choices = anchors.choices
        guard down, !done, !choices.paused, choices.snap || choices.behavior.unsnapRestore, isMoving(p),
              choices.snap, let w = win
        else { return }
        stashAt = anchors.pinned(w) ? nil : stash?.edge(p, held)
        if stashAt != nil {
            hide()
            return
        }
        let screens = platform.screens.current()
        guard let i = screens.full.firstIndex(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h })
        else {
            hide()
            return
        }
        let ch = i == screens.ultrawide ? anchors.channel(screens.usable[i]) : nil
        var prev: String?
        if case let .zone(z) = drop {
            prev = z
        }
        let next: SnapDrop? = if let z = panel?.zone(at: p, window: w, held: held, option: option) {
            .zone(z)
        } else {
            Snap.drop(SnapPoint(p.x, p.y), screens.full[i], ch, prev: prev, option: option, parkable: true,
                      pinned: anchors.pinned(w), castOff: anchors.isCastOff(w.id), snapping: choices.snapping,
                      held: held)
        }
        if next == drop && i == screen {
            return
        }
        drop = next
        screen = i
        let frame: Frame? = switch next {
        case let .park(key):
            SlotKey(rawValue: key).map { anchors.slotFrame(screens.usable[i], $0) }
        case let .zone(name):
            preview(name, current(w), screens, i)
        case .none:
            nil
        }
        guard let frame else {
            platform.overlay.hide()
            return
        }
        let style = choices.snapping.footprint
        platform.overlay.show(frame, style: style, palette: .harbor)
        showed(frame, style)
    }

    // ended finishes the drag: a drop in a zone runs its action, a drop on a slot anchors the app, and
    // a Command-drag at an edge stashes the window. A window that can no longer be read gets nothing.
    public func ended(held: Set<String>) {
        let (w, drop, screen, stashAt, start, moved) = (win, drop, screen, stashAt, start, moving == true)
        reset()
        guard moved, var w else { return }
        guard let f = platform.windows.frame(w.id) else { return }
        w.frame = f
        if let stashAt, let stash {
            stash.stash(w, stashAt, start)
            return
        }
        defer { dropped(w.id, drop) }
        switch drop {
        case let .park(key):
            guard let slot = SlotKey(rawValue: key) else { return }
            anchors.assign(slot, w.bundle)
            platform.notifier.notify("\(appName(w.bundle)) anchored", "It holds the \(slot.title.lowercased()) slot now. "
                + "Unanchor it from the Moorings menu to free the slot.")
            changed()
        case let .zone(name):
            apply(name, w, platform.screens.current(), screen)
        case .none:
            break
        }
    }

    // cancel forgets the drag without a drop.
    public func cancel() {
        reset()
    }

    // hide clears the drop and takes the footprint away.
    private func hide() {
        drop = nil
        platform.overlay.hide()
    }

    // current returns w at the frame the store reads now, or its last read frame when it cannot.
    private func current(_ w: WindowInfo) -> WindowInfo {
        var at = w
        at.frame = platform.windows.frame(w.id) ?? w.frame
        return at
    }

    // reset forgets the drag and removes the footprint and the panel.
    private func reset() {
        platform.overlay.hide()
        panel?.reset()
        down = false
        done = false
        given = nil
        win = nil
        start = nil
        checks = 0
        firstRead = nil
        moving = nil
        from = nil
        drop = nil
        screen = nil
        at = nil
        placedFrame = nil
        stashAt = nil
    }

    // isMoving reports whether the drag moves a window, reading it once the pointer at p has traveled
    // since the last read.
    private func isMoving(_ p: Point) -> Bool {
        if moving == true {
            return true
        }
        if let from, abs(p.x - from.x) + abs(p.y - from.y) < Self.travel {
            return false
        }
        from = p
        look()
        return moving == true && !done
    }

    // look reads the dragged window: the given or focused window the first time, then its frame,
    // until it moves, resizes, or Behavior.stillDrag gives up on it. A snapped window that starts
    // moving gets its size from before the snap back.
    private func look() {
        guard let w = win, let s = start else {
            let scan = platform.windows.scan(platform.screens.current(), full: false)
            guard let found = given.map({ id in scan.windows.first { $0.id == id } }) ?? scan.focused else {
                done = true
                return
            }
            win = found
            start = found.frame
            if let at, let from, let p = placed(found.id), !anchors.pinned(found),
               Behavior.snapped(p, start: found.frame, moved: abs(from.x - at.x) + abs(from.y - at.y)) {
                placedFrame = p
            }
            return
        }
        guard let f = platform.windows.frame(w.id) else {
            done = true
            return
        }
        if abs(f.w - s.w) > Self.sizeTolerance || abs(f.h - s.h) > Self.sizeTolerance {
            done = true
        } else if f.x != s.x || f.y != s.y {
            moving = true
            if let p = placedFrame, let at, anchors.choices.behavior.unsnapRestore {
                placedFrame = nil
                unsnap(w, f, at.x - p.x)
            }
        } else {
            checks += 1
            let now = platform.clock.now
            let first = firstRead ?? now
            firstRead = first
            done = Behavior.stillDrag(reads: checks, seconds: now - first)
        }
    }
}
