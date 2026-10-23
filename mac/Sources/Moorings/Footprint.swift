import AppKit

import MooringsCore

// Footprint is the borderless panel that shows where a dragged window will land.
@MainActor
final class Footprint {
    // panel is the footprint window, nil while hidden.
    private var panel: NSPanel?

    // show draws the footprint at frame, in global top-left coordinates, in palette's accent.
    func show(_ frame: Frame, palette: Palette) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.x, y: primary - frame.y - frame.h, width: frame.w, height: frame.h)
        if let panel {
            panel.setFrame(rect, display: true)
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
        view.layer?.borderWidth = 2
        view.layer?.backgroundColor = Self.color(palette.footprintFill).cgColor
        view.layer?.borderColor = Self.color(palette.footprintStroke).cgColor
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
    }

    // hide removes the footprint.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
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

    // init builds a drag follower for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // pressed starts following a new drag.
    func pressed() {
        reset()
        down = true
    }

    // dragged follows the cursor at p and moves the footprint when the zone changes.
    func dragged(_ p: CGPoint, option: Bool) {
        let choices = app.anchors.choices
        guard down, !done, !choices.paused, choices.snap, isMoving(p), let w = win else { return }
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
                             parkable: true, pinned: app.anchors.pinned(w), castOff: app.anchors.isCastOff(w.id))
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
            footprint.show(frame, palette: choices.theme.palette)
        } else {
            footprint.hide()
        }
    }

    // released snaps the window, or anchors its app, when the drag ended in a zone. The work runs
    // after the event, so the tap never waits on a window.
    func released() {
        let (w, drop, screen) = (win, drop, screen)
        reset()
        guard var w, let drop else { return }
        DispatchQueue.main.async { [app] in
            switch drop {
            case let .park(key):
                guard let slot = SlotKey(rawValue: key) else { return }
                app.anchors.assign(slot, w.bundle)
                app.logger.notice("TODO banner: \(w.bundle, privacy: .public) anchored by an Option drop")
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
    // moves, resizes, or maxChecks reads pass.
    private func look() {
        guard let w = win, let s = start else {
            guard let focused = app.windows.scan(Screens.current()).focused else {
                done = true
                return
            }
            win = focused
            start = focused.frame
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
        } else {
            checks += 1
            done = checks >= Self.maxChecks
        }
    }
}
