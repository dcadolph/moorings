import AppKit
import Carbon.HIToolbox
import os

import MooringsCore

// TriggerOverlay throws a window while the overlay's trigger key is held. Moving the pointer picks
// one of 16 targets by direction and distance, and arrow keys pick a span on a keyboard grid. A
// footprint previews the pick, and letting go of the trigger applies it to the window that was
// under the pointer when the trigger went down, else the focused one. Escape, or letting go inside
// the dead zone, does nothing. Nothing runs while the trigger is up: no timer and no grabbed keys.
@MainActor
final class TriggerOverlay {
    // tickSeconds is how often the pointer is read while the trigger is held.
    static let tickSeconds = 1.0 / 60

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why a hold did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "overlay")
    // footprint previews the pick.
    private let footprint = Footprint()
    // gridPanel draws the keyboard grid.
    private let gridPanel = GridPanel()
    // held reports whether the trigger is down.
    private var held = false
    // done reports whether this hold is over: canceled, applied by Return, or without a window.
    private var done = false
    // origin is where the pointer was when the trigger went down, in top-left coordinates.
    private var origin = CGPoint.zero
    // target is the window the hold acts on, nil until it is read after the trigger goes down.
    private var target: WindowInfo?
    // pick is the cursor picker's current action, nil inside the dead zone.
    private var pick: String?
    // grid is the keyboard grid's span, nil until a grid key is pressed.
    private var grid: OverlayGrid?
    // area is the area the grid divides, the target's own.
    private var area: Frame?
    // timer reads the pointer while the trigger is held.
    private var timer: Timer?

    // init builds an overlay for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // flagsChanged starts a hold when flags show the trigger down and ends it when they no longer do.
    // It runs inside the event tap, so it reads no window.
    func flagsChanged(_ flags: CGEventFlags, at p: CGPoint) {
        let down = app.anchors.choices.overlay.trigger.held(flags.rawValue)
        if down, !held {
            begin(at: p)
        } else if !down, held {
            end()
        }
    }

    // begin starts a hold at p, grabbing the grid keys and starting the pointer timer, then reads the
    // target after the event.
    private func begin(at p: CGPoint) {
        held = true
        done = false
        origin = p
        target = nil
        pick = nil
        grid = nil
        area = nil
        let choices = app.anchors.choices
        guard !choices.paused, app.hotkeys.enabled, app.windows.trusted, NSEvent.pressedMouseButtons == 0 else {
            done = true
            return
        }
        app.hotkeys.grab(Self.keys(choices.overlay.trigger))
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        DispatchQueue.main.async { [self] in
            guard held, !done else { return }
            let scan = app.windows.scan(Screens.current())
            let hit = Windows.hit(origin)?.id
            let w = scan.windows.first { $0.id == hit && !$0.isFilePanel } ?? scan.focused
            guard let w, !app.anchors.pinned(w), !w.isFullScreen else {
                logger.notice("overlay: no window to throw under the pointer or in front")
                done = true
                return
            }
            target = w
        }
    }

    // end finishes a hold: it applies the grid span when a grid key was used, else the cursor pick.
    private func end() {
        let (w, pick, grid, area, done) = (target, pick, grid, area, done)
        held = false
        reset()
        guard !done, let w, NSEvent.pressedMouseButtons == 0 else { return }
        if let grid, let area {
            app.actions.applyFrame(grid.frame(area, gap: app.anchors.choices.gapPx), to: w.id)
        } else if let pick {
            app.actions.run(pick, window: w.id)
        }
    }

    // reset stops the timer, lets the grid keys go and hides the preview.
    private func reset() {
        timer?.invalidate()
        timer = nil
        app.hotkeys.ungrab()
        footprint.hide()
        gridPanel.hide()
    }

    // tick reads the pointer and moves the preview when the pick changes. The grid, once used, owns
    // the preview.
    private func tick() {
        guard held, !done, grid == nil, let w = target else { return }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        let next = Overlay.pick(dx: loc.x - origin.x, dy: primary - loc.y - origin.y)
        guard next != pick else { return }
        pick = next
        guard let next, let f = app.actions.frame(next, for: w, screens: Screens.current()).0 else {
            footprint.hide()
            return
        }
        show(f)
    }

    // key handles a grabbed key by its tag: move or grow the grid span, apply it, or cancel.
    func key(_ tag: String) {
        guard held, !done else { return }
        switch tag {
        case "escape":
            done = true
            reset()
        case "return":
            guard let grid, let area, let w = target else { return }
            done = true
            reset()
            app.actions.applyFrame(grid.frame(area, gap: app.anchors.choices.gapPx), to: w.id)
        default:
            guard let w = target, let step = Self.step(tag) else { return }
            let choices = app.anchors.choices
            let a = area ?? app.actions.area(for: w, screens: Screens.current())
            let primary = NSScreen.screens.first?.frame.height ?? 0
            let loc = NSEvent.mouseLocation
            var g = grid ?? OverlayGrid(cols: choices.overlay.gridColumns, rows: choices.overlay.gridRows,
                                        at: Point(x: loc.x, y: primary - loc.y), in: a)
            if grid != nil {
                g = tag.hasPrefix("grow-") ? g.grown(step) : g.moved(step)
            }
            area = a
            grid = g
            pick = nil
            footprint.hide()
            gridPanel.show(g, in: a, gap: choices.gapPx, palette: choices.theme.palette,
                           style: choices.snapping.footprint)
        }
    }

    // show draws the footprint at f in the snapping style.
    private func show(_ f: Frame) {
        let choices = app.anchors.choices
        footprint.show(f, palette: choices.theme.palette, style: choices.snapping.footprint)
    }

    // step returns the direction a grid key's tag names.
    private static func step(_ tag: String) -> OverlayStep? {
        switch tag.split(separator: "-").last {
        case "left": .left
        case "right": .right
        case "up": .up
        case "down": .down
        default: nil
        }
    }

    // keys lists the keys a hold of trigger grabs: arrows move the span and Shift-arrows grow it, under
    // the trigger's own modifier, plus Return, Enter and Escape. Fn has no Carbon modifier, so for Fn
    // the bare keys are grabbed, with Home, End, Page Up and Page Down standing in for the arrows Fn
    // turns into them.
    static func keys(_ trigger: OverlayTrigger) -> [(key: String, mods: UInt32, tag: String)] {
        let mods: UInt32 = switch trigger {
        case .rightOption: UInt32(optionKey)
        case .rightCommand: UInt32(cmdKey)
        case .rightControl: UInt32(controlKey)
        case .fn, .none: 0
        }
        var arrows = [("left", "left"), ("right", "right"), ("up", "up"), ("down", "down")]
        if trigger == .fn {
            arrows += [("home", "left"), ("end", "right"), ("pageup", "up"), ("pagedown", "down")]
        }
        var out: [(key: String, mods: UInt32, tag: String)] = []
        for (key, dir) in arrows {
            out.append((key, mods, "move-\(dir)"))
            out.append((key, mods | UInt32(shiftKey), "grow-\(dir)"))
        }
        out += [("return", mods, "return"), ("enter", mods, "return"), ("escape", mods, "escape")]
        return out
    }
}

// GridPanel is the borderless panel that draws the keyboard grid over an area, with the picked span
// filled.
@MainActor
final class GridPanel {
    // panel is the grid window, nil while hidden.
    private var panel: NSPanel?
    // view draws the cells.
    private let view = GridView()

    // show draws grid over area, in global top-left coordinates, in style's colors on palette.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, palette: Palette, style: FootprintStyle) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: area.x, y: primary - area.y - area.h, width: area.w, height: area.h)
        let (fill, stroke) = style.tints(palette)
        view.cells = (0..<grid.cols).flatMap { c in
            (0..<grid.rows).map { r in Self.local(Geometry.part(area, c, c + 1, grid.cols, r, r + 1, grid.rows), area) }
        }
        view.span = Self.local(grid.frame(area, gap: gap), area)
        view.fill = Footprint.color(fill)
        view.stroke = Footprint.color(stroke)
        view.needsDisplay = true
        let p = panel ?? makePanel(rect)
        panel = p
        p.setFrame(rect, display: true)
        p.orderFrontRegardless()
    }

    // hide removes the grid.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // local turns f, in global top-left coordinates, into the view's bottom-left coordinates over area.
    private static func local(_ f: Frame, _ area: Frame) -> NSRect {
        NSRect(x: f.x - area.x, y: area.y + area.h - f.y - f.h, width: f.w, height: f.h)
    }

    // makePanel builds the grid window at rect.
    private func makePanel(_ rect: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: rect.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        return p
    }
}

// GridView draws the grid's cell outlines and fills the picked span.
final class GridView: NSView {
    // cells lists every cell's rect.
    var cells: [NSRect] = []
    // span is the picked span's rect.
    var span = NSRect.zero
    // fill colors the span.
    var fill = NSColor.clear
    // stroke outlines the cells and the span.
    var stroke = NSColor.clear

    // draw outlines each cell and fills the span.
    override func draw(_ dirtyRect: NSRect) {
        stroke.withAlphaComponent(stroke.alphaComponent * 0.5).setStroke()
        for c in cells {
            let path = NSBezierPath(rect: c.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
        fill.setFill()
        let s = NSBezierPath(roundedRect: span, xRadius: 8, yRadius: 8)
        s.fill()
        stroke.setStroke()
        s.lineWidth = 2
        s.stroke()
    }
}
