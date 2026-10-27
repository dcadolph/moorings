import AppKit
import Carbon.HIToolbox
import os

import MooringsCore

// holdBlocker names why a held-key throw or hover may not start, or returns nil when it may.
@MainActor
func holdBlocker(_ app: AppDelegate) -> String? {
    if app.anchors.choices.paused {
        return "moorings is paused"
    }
    if !app.hotkeys.enabled {
        return "shortcuts are off"
    }
    if !app.windows.trusted {
        return "no Accessibility access"
    }
    if NSEvent.pressedMouseButtons != 0 {
        return "a mouse button is down"
    }
    return nil
}

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
        app.gridPicker.cancel()
        held = true
        done = false
        origin = p
        target = nil
        pick = nil
        grid = nil
        area = nil
        if let why = holdBlocker(app) {
            logger.notice("overlay: trigger held but \(why, privacy: .public): nothing to throw")
            done = true
            return
        }
        app.hotkeys.grab(Self.keys(app.anchors.choices.overlay.trigger))
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
    // The move runs on the next main queue turn, outside the tap callback that saw the key go up.
    private func end() {
        let (w, pick, grid, area, done) = (target, pick, grid, area, done)
        held = false
        reset()
        guard !done, let w else { return }
        guard NSEvent.pressedMouseButtons == 0 else {
            logger.notice("overlay: trigger let go while a mouse button is down: nothing thrown")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let grid, let area {
                app.actions.applyFrame(grid.frame(area, gap: app.anchors.choices.gapPx), to: w.id)
            } else if let pick {
                app.actions.run(pick, window: w.id)
            }
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
            gridPanel.show(g, in: a, gap: choices.gapPx, palette: .harbor,
                           style: choices.snapping.footprint)
        }
    }

    // show draws the footprint at f in the snapping style.
    private func show(_ f: Frame) {
        let choices = app.anchors.choices
        footprint.show(f, palette: .harbor, style: choices.snapping.footprint)
    }

    // step returns the direction a grid key's tag names.
    static func step(_ tag: String) -> OverlayStep? {
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
// filled. A panel built with a mouse handler takes clicks and drags on the grid without bringing
// Moorings forward; one without lets every click through.
@MainActor
final class GridPanel {
    // panel is the grid window, nil while hidden.
    private var panel: NSPanel?
    // view draws the cells.
    private let view = GridView()

    // init builds a grid panel that reports presses, drags and releases on it to onMouse, or one that
    // ignores the mouse when onMouse is nil.
    init(onMouse: ((GridMouse, Point) -> Void)? = nil) {
        view.onMouse = onMouse
    }

    // contains reports whether p, in global top-left coordinates, is on the shown grid.
    func contains(_ p: CGPoint) -> Bool {
        guard let panel else { return false }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return panel.frame.contains(CGPoint(x: p.x, y: primary - p.y))
    }

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
        p.ignoresMouseEvents = view.onMouse == nil
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: rect.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        return p
    }
}

// GridMouse is what the mouse did on a grid that takes clicks.
enum GridMouse {
    case down, drag, up
}

// GridView draws the grid's cell outlines and fills the picked span, and reports the mouse on it when
// it has a handler.
final class GridView: NSView {
    // onMouse is told each press, drag and release with the pointer in global top-left coordinates.
    var onMouse: ((GridMouse, Point) -> Void)?
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

    // acceptsFirstMouse takes the first click, since the grid's panel never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // mouseDown reports a press.
    override func mouseDown(with event: NSEvent) {
        report(.down)
    }

    // mouseDragged reports a drag.
    override func mouseDragged(with event: NSEvent) {
        report(.drag)
    }

    // mouseUp reports a release.
    override func mouseUp(with event: NSEvent) {
        report(.up)
    }

    // report passes phase and the pointer to onMouse.
    private func report(_ phase: GridMouse) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        onMouse?(phase, Point(x: loc.x, y: primary - loc.y))
    }
}

// GridPicker pops a grid of cells over a window's area for a grid action. Dragging across cells picks
// a span and letting go fills it, and a click picks one cell. Arrow keys move the span, Shift-arrows
// grow it and Return applies it. Escape, or a click off the grid, puts it away. While it shows, the
// arrow, Return and Escape keys go to Moorings.
@MainActor
final class GridPicker {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why a grid did not open.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "overlay")
    // panel draws the grid and takes the mouse on it.
    private lazy var panel = GridPanel { [unowned self] phase, p in mouse(phase, p) }
    // target is the window the grid places, nil while hidden.
    private var target: WindowID?
    // area is the area the grid divides.
    private var area = Frame(x: 0, y: 0, w: 0, h: 0)
    // grid is the picked span.
    private var grid: OverlayGrid?
    // press is where a press on the grid went down, nil when no button is down on it.
    private var press: Point?

    // init builds a grid picker for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // showing reports whether the grid is up.
    var showing: Bool { target != nil }

    // show pops a grid of cols by rows over the area of the window with id window, or of the focused
    // window when nil, and reports whether it opened. Pinned and fullscreen windows get none.
    func show(cols: Int, rows: Int, window: WindowID?) -> Bool {
        cancel()
        let screens = Screens.current()
        let scan = app.windows.scan(screens)
        guard let w = window.flatMap({ id in scan.windows.first { $0.id == id } }) ?? scan.focused,
              !app.anchors.pinned(w), !w.isFullScreen
        else {
            logger.notice("grid: no free window in front")
            return false
        }
        let a = app.actions.area(for: w, screens: screens)
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        var start = Point(x: loc.x, y: primary - loc.y)
        if start.x < a.x || start.x >= a.x + a.w || start.y < a.y || start.y >= a.y + a.h {
            start = Point(x: w.frame.x + w.frame.w / 2, y: w.frame.y + w.frame.h / 2)
        }
        target = w.id
        area = a
        grid = OverlayGrid(cols: cols, rows: rows, at: start, in: a)
        app.hotkeys.grab(TriggerOverlay.keys(.none))
        draw()
        return true
    }

    // contains reports whether p, in global top-left coordinates, is on the grid.
    func contains(_ p: CGPoint) -> Bool {
        showing && panel.contains(p)
    }

    // cancel puts the grid away without moving anything.
    func cancel() {
        guard showing else { return }
        target = nil
        grid = nil
        press = nil
        app.hotkeys.ungrab()
        panel.hide()
    }

    // key handles a grabbed key by its tag: move or grow the span, apply it, or cancel.
    func key(_ tag: String) {
        guard showing, let g = grid else { return }
        switch tag {
        case "escape":
            cancel()
        case "return":
            apply()
        default:
            guard let step = TriggerOverlay.step(tag) else { return }
            grid = tag.hasPrefix("grow-") ? g.grown(step) : g.moved(step)
            draw()
        }
    }

    // mouse picks the span from where the press went down to the pointer, and applies it on release.
    private func mouse(_ phase: GridMouse, _ p: Point) {
        guard showing, let g = grid else { return }
        if phase == .down {
            press = p
        }
        guard let from = press else { return }
        grid = OverlayGrid(cols: g.cols, rows: g.rows, from: from, to: p, in: area)
        if phase == .up {
            apply()
        } else {
            draw()
        }
    }

    // apply puts the grid away and fills the picked span with the target window.
    private func apply() {
        guard let id = target, let g = grid else { return }
        let f = g.frame(area, gap: app.anchors.choices.gapPx)
        cancel()
        app.actions.applyFrame(f, to: id)
    }

    // draw shows the grid with the picked span filled.
    private func draw() {
        guard let g = grid else { return }
        let choices = app.anchors.choices
        panel.show(g, in: area, gap: choices.gapPx, palette: .harbor, style: choices.snapping.footprint)
    }
}

// HoverMover moves or resizes the window under the pointer while the hover modifiers are held and no
// button is down. It reads the pointer on a timer only while they are held, so it costs nothing at
// rest, and it leaves pinned, fullscreen, stashed windows and file panels alone.
@MainActor
final class HoverMover {
    // tickSeconds is how often the pointer is read while the modifiers are held.
    static let tickSeconds = 1.0 / 60

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // logger writes why a hover did nothing.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "overlay")
    // mode is what the held modifiers do, nil while none are held.
    private var mode: HoverMode?
    // origin is where the pointer was when the modifiers went down, in top-left coordinates.
    private var origin = CGPoint.zero
    // target is the window being moved, nil until it is read after the modifiers go down.
    private var target: WindowID?
    // start is the target's frame when the modifiers went down.
    private var start = Frame(x: 0, y: 0, w: 0, h: 0)
    // corner is the corner that follows the pointer in a resize.
    private var corner = HoverCorner.bottomRight
    // last is the pointer offset last applied, so a still pointer writes nothing.
    private var last: Point?
    // timer reads the pointer while the modifiers are held.
    private var timer: Timer?

    // init builds a hover mover for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // active reports whether a hover holds a window, so the layout treats it as a window being dragged.
    var active: Bool { target != nil }

    // flagsChanged starts, switches or ends a hover as the held modifiers change. It runs inside the
    // event tap, so it reads no window.
    func flagsChanged(_ flags: CGEventFlags, at p: CGPoint) {
        let choices = app.anchors.choices
        let next = choices.overlay.trigger.held(flags.rawValue) ? nil : Hover.mode(flags.rawValue, choices.overlay)
        guard next != mode else { return }
        end()
        if let next {
            begin(next, at: p)
        }
    }

    // begin starts a hover of mode at p and reads the window under p after the event.
    private func begin(_ mode: HoverMode, at p: CGPoint) {
        if let why = holdBlocker(app) {
            logger.notice("hover: keys held but \(why, privacy: .public): nothing moves")
            return
        }
        self.mode = mode
        origin = p
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickSeconds, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        DispatchQueue.main.async { [self] in
            guard self.mode == mode, target == nil else { return }
            let hit = Windows.hit(origin)?.id
            guard let w = app.windows.scan(Screens.current()).windows.first(where: { $0.id == hit && !$0.isFilePanel }),
                  !app.anchors.pinned(w), !w.isFullScreen, !app.anchors.stashed.contains(w.id)
            else {
                logger.notice("hover: no free window under the pointer")
                return
            }
            app.anchors.save(w)
            target = w.id
            start = w.frame
            corner = Hover.corner(w.frame, nearest: Point(x: origin.x, y: origin.y))
            last = nil
        }
    }

    // end stops a hover and lets the layout look at where the window landed.
    private func end() {
        let moved = target != nil
        timer?.invalidate()
        timer = nil
        mode = nil
        target = nil
        if moved {
            app.wake()
        }
    }

    // tick moves the target by how far the pointer has gone since the modifiers went down. Nothing
    // moves while a button is down.
    private func tick() {
        guard let mode, let id = target, NSEvent.pressedMouseButtons == 0 else { return }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let loc = NSEvent.mouseLocation
        let d = Point(x: (loc.x - origin.x).rounded(), y: (primary - loc.y - origin.y).rounded())
        guard d != last else { return }
        last = d
        let f = Hover.frame(mode, start: start, corner: corner, dx: d.x, dy: d.y)
        if mode == .move {
            app.windows.position(id, x: f.x, y: f.y)
            return
        }
        app.windows.move(id, to: f)
        if let got = app.windows.frame(id), got.w != f.w || got.h != f.h {
            let kept = Hover.keep(f, corner: corner, w: got.w, h: got.h)
            app.windows.position(id, x: kept.x, y: kept.y)
        }
    }
}
