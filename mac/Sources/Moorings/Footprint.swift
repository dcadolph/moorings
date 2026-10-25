import AppKit

import MooringsCore

// Footprint is the borderless panel that shows where a dragged window will land.
@MainActor
final class Footprint {
    // panel is the footprint window, nil while hidden.
    private var panel: NSPanel?

    // fadeTime is how long the shown footprint takes to fade out.
    private var fadeTime = 0.0

    // show draws the footprint at frame, in global top-left coordinates, in style's colors on palette, fading
    // it in when style fades.
    func show(_ frame: Frame, palette: Palette, style: FootprintStyle) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.x, y: primary - frame.y - frame.h, width: frame.w, height: frame.h)
        fadeTime = style.fadeTime
        if let panel {
            Self.paint(panel.contentView, palette: palette, style: style)
            if fadeTime > 0 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = fadeTime
                    panel.animator().setFrame(rect, display: true)
                }
            } else {
                panel.setFrame(rect, display: true)
            }
            return
        }
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        Self.paint(view, palette: palette, style: style)
        p.contentView = view
        panel = p
        guard fadeTime > 0 else {
            p.orderFrontRegardless()
            return
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeTime
            p.animator().alphaValue = 1
        }
    }

    // hide removes the footprint, fading it out when it faded in.
    func hide() {
        guard let p = panel else { return }
        panel = nil
        guard fadeTime > 0 else {
            p.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeTime
            p.animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
    }

    // paint colors view's layer from style on palette.
    private static func paint(_ view: NSView?, palette: Palette, style: FootprintStyle) {
        let (fill, stroke) = style.tints(palette)
        view?.layer?.borderWidth = max(0, style.borderWidth)
        view?.layer?.backgroundColor = color(fill).cgColor
        view?.layer?.borderColor = color(stroke).cgColor
    }

    // color returns tint as a color.
    static func color(_ tint: Tint) -> NSColor {
        NSColor(srgbRed: tint.color.red, green: tint.color.green, blue: tint.color.blue, alpha: tint.alpha)
    }
}

// DragSnap follows a drag and snaps the dragged window to the zone under the cursor when the
// button comes up, or anchors its app with Option over a strip. It never reads a window inside
// the tap: reads run after the event, one at a time, once the cursor has traveled.
@MainActor
final class DragSnap {
    // travel is how many points the cursor must move between reads of the dragged window.
    static let travel = 8.0
    // maxChecks is how many reads may find the window still before the drag is taken as not
    // moving a window.
    static let maxChecks = 3

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // footprint shows the zone.
    private let footprint = Footprint()
    // down reports whether the primary button is down for a drag that may snap.
    private var down = false
    // done reports whether this drag will not snap.
    private var done = false
    // win is the dragged window, nil until the first read.
    private var win: WindowInfo?
    // start is the dragged window's frame at the first read.
    private var start: Frame?
    // checks counts the reads that found the window still.
    private var checks = 0
    // moving reports whether the drag is moving the window.
    private var moving = false
    // from is where the cursor was at the last read.
    private var from: CGPoint?
    // pending reports whether a read is queued.
    private var pending = false
    // drag counts drags, so a read queued for an earlier drag changes nothing.
    private var drag = 0
    // drop is the zone or park slot under the cursor.
    private var drop: SnapDrop?
    // screen is the index of the screen the drop is on.
    private var screen: Int?
    // at is where the button went down.
    private var at: CGPoint?
    // placed is the frame the dragged window's last action gave it, nil unless the window still sat
    // there when the drag began.
    private var placed: Frame?
    // stashAt is the edge a Command-drag would stash the window at, nil when it would not.
    private var stashAt: StashEdge?

    // init builds a drag follower for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // pressed starts following a new drag from p.
    func pressed(_ p: CGPoint) {
        reset()
        down = true
        at = p
    }

    // held returns the names of the snap modifiers down in flags.
    static func held(_ flags: CGEventFlags) -> Set<String> {
        let names: [(CGEventFlags, String)] = [(.maskShift, "shift"), (.maskControl, "control"),
                                               (.maskAlternate, "option"), (.maskCommand, "command")]
        return Set(names.filter { flags.contains($0.0) }.map(\.1))
    }

    // dragged follows the cursor at p with flags down and moves the footprint when the zone changes, with a
    // haptic tap when the style asks for one.
    func dragged(_ p: CGPoint, flags: CGEventFlags) {
        let option = flags.contains(.maskAlternate)
        let choices = app.anchors.choices
        guard down, !done, !choices.paused, choices.snap || choices.behavior.unsnapRestore, isMoving(p),
              choices.snap, let w = win
        else { return }
        stashAt = app.anchors.pinned(w) ? nil : app.stasher.dropEdge(p, flags: flags)
        if stashAt != nil {
            drop = nil
            footprint.hide()
            return
        }
        let screens = Screens.current()
        guard let i = screens.full.firstIndex(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h })
        else {
            drop = nil
            footprint.hide()
            return
        }
        let ch = i == screens.ultrawide ? app.anchors.channel(screens.usable[i]) : nil
        var prev: String?
        if case let .zone(z) = drop {
            prev = z
        }
        let next = Snap.drop(SnapPoint(p.x, p.y), screens.full[i], ch, prev: prev, option: option,
                             parkable: true, pinned: app.anchors.pinned(w), castOff: app.anchors.isCastOff(w.id),
                             snapping: choices.snapping, held: Self.held(flags))
        if next == drop && i == screen {
            return
        }
        drop = next
        screen = i
        var frame: Frame?
        switch next {
        case let .park(key):
            frame = SlotKey(rawValue: key).map { app.anchors.slotFrame(screens.usable[i], $0) }
        case let .zone(name):
            var at = w
            at.frame = app.windows.frame(w.id) ?? w.frame
            frame = app.actions.frame(name, for: at, screens: screens, index: i).0
        case .none:
            frame = nil
        }
        if let frame {
            let style = choices.snapping.footprint
            footprint.show(frame, palette: choices.theme.palette, style: style)
            if style.haptic {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else {
            footprint.hide()
        }
    }

    // released snaps the window, or anchors its app, when the drag ended in a zone, or stashes it when a
    // Command-drag ended at an edge. The work runs after the event, so the tap never waits on a window.
    func released() {
        let (w, drop, screen, stashAt) = (win, drop, screen, stashAt)
        reset()
        if var w, let stashAt {
            DispatchQueue.main.async { [app] in
                w.frame = app.windows.frame(w.id) ?? w.frame
                app.stasher.stash(w, edge: stashAt)
            }
            return
        }
        guard var w, let drop else { return }
        DispatchQueue.main.async { [app] in
            switch drop {
            case let .park(key):
                guard let slot = SlotKey(rawValue: key) else { return }
                app.anchors.assign(slot, w.bundle)
                app.notify("\(app.appName(w.bundle)) anchored", "It holds the \(slot.title.lowercased()) slot now. "
                    + "Unanchor it from the Moorings menu to free the slot.")
                app.save()
            case let .zone(name):
                let screens = Screens.current()
                w.frame = app.windows.frame(w.id) ?? w.frame
                app.actions.apply(name, to: w, screens: screens, index: screen)
            }
        }
    }

    // reset forgets the drag and removes the footprint.
    private func reset() {
        footprint.hide()
        drag += 1
        down = false
        done = false
        win = nil
        start = nil
        checks = 0
        moving = false
        from = nil
        pending = false
        drop = nil
        screen = nil
        at = nil
        placed = nil
        stashAt = nil
    }

    // isMoving reports whether the drag is moving a window, queueing one read of it at a time once
    // the cursor at p has traveled since the last read.
    private func isMoving(_ p: CGPoint) -> Bool {
        if moving {
            return true
        }
        if pending {
            return false
        }
        if let from, abs(p.x - from.x) + abs(p.y - from.y) < Self.travel {
            return false
        }
        from = p
        pending = true
        let this = drag
        DispatchQueue.main.async { [weak self] in
            guard let self, self.drag == this else { return }
            self.pending = false
            self.look()
        }
        return false
    }

    // look reads the dragged window: the focused window the first time, then its frame, until it
    // moves, resizes, or maxChecks reads pass. A snapped window that starts moving gets its size from
    // before the snap back.
    private func look() {
        guard let w = win, let s = start else {
            guard let focused = app.windows.scan(Screens.current()).focused else {
                done = true
                return
            }
            win = focused
            start = focused.frame
            if let at, let from, let p = app.actions.placed(focused.id), !app.anchors.pinned(focused),
               Behavior.snapped(p, start: focused.frame, moved: abs(from.x - at.x) + abs(from.y - at.y)) {
                placed = p
            }
            return
        }
        guard let f = app.windows.frame(w.id) else {
            done = true
            return
        }
        if f.w != s.w || f.h != s.h {
            done = true
        } else if f.x != s.x || f.y != s.y {
            moving = true
            if let p = placed, let at, app.anchors.choices.behavior.unsnapRestore {
                placed = nil
                app.actions.unsnap(w, at: f, grab: at.x - p.x)
            }
        } else {
            checks += 1
            done = checks >= Self.maxChecks
        }
    }
}

// StackBadge is the small count that sits on the top-right corner of a stacked window while the
// pointer rests at that window's top-left corner.
@MainActor
final class StackBadge {
    // restMove is the most in points the pointer may move between two ticks and still count as
    // resting.
    static let restMove = 2.0

    // panel is the badge window, nil until first shown.
    private var panel: NSPanel?
    // label draws the count.
    private let label = NSTextField(labelWithString: "")
    // pointer is the pointer position at the previous tick.
    private var pointer: Point?
    // settled reports whether the badge was already worked out for the current rest.
    private var settled = false

    // update runs once a tick. Any move of more than restMove hides the badge and restarts the rest.
    // On the first tick of a rest it shows the count of the stack whose front window has its
    // top-left corner under the pointer, or hides the badge when there is none. It reads the window
    // list once per rest, never while the pointer moves or stays still, and hides the badge while a
    // mouse button is down.
    func update(palette: Palette, choices: StackChoices, gap: Double) {
        guard NSEvent.pressedMouseButtons == 0 else {
            hide()
            pointer = nil
            return
        }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        let p = Point(x: loc.x, y: primary - loc.y)
        defer { pointer = p }
        guard let last = pointer, abs(p.x - last.x) <= Self.restMove, abs(p.y - last.y) <= Self.restMove else {
            hide()
            settled = false
            return
        }
        guard !settled else { return }
        settled = true
        let frames = Self.frames()
        guard let i = Tile.hovered(at: p, frames: frames, gap: gap) else { return }
        let n = Tile.stack(anchorOf: i, among: frames, choices: choices).count
        if n > 1 {
            show(n, at: frames[i], primary: primary, palette: palette)
        }
    }

    // hide removes the badge.
    func hide() {
        panel?.orderOut(nil)
    }

    // frames lists the frames of the visible normal windows on screen, front to back, leaving out
    // Moorings' own.
    private static func frames() -> [Frame] {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != own,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = info[kCGWindowBounds as String] as? [String: Double],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { return nil }
            return Frame(x: x, y: y, w: w, h: h)
        }
    }

    // show draws count at the top-right corner of front.
    private func show(_ count: Int, at front: Frame, primary: Double, palette: Palette) {
        let size = NSSize(width: 30, height: 22)
        let rect = NSRect(x: front.x + front.w - size.width - 8, y: primary - front.y - size.height - 8,
                          width: size.width, height: size.height)
        let p = panel ?? makePanel(rect)
        panel = p
        p.contentView?.layer?.backgroundColor = BannerPanel.color(palette.accent).cgColor
        label.textColor = BannerPanel.color(palette.onAccent)
        label.stringValue = "\(count)"
        p.setFrame(rect, display: true)
        p.orderFrontRegardless()
    }

    // makePanel builds the badge window at rect.
    private func makePanel(_ rect: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = rect.height / 2
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (rect.height - 16) / 2, width: rect.width, height: 16)
        label.autoresizingMask = [.width]
        view.addSubview(label)
        p.contentView = view
        return p
    }
}
