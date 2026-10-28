import MooringsCore

// GridPicker pops a grid of cells over a window's area for a grid action. Dragging across cells picks
// a span and letting go fills it, and a click picks one cell. Arrow keys move the span, Shift-arrows
// grow it and Return applies it. Escape, or a click off the grid, puts it away. While it shows, the
// platform grabs the arrow, Return and Escape keys and reports them by the tags TriggerOverlay names.
public final class GridPicker {
    // pointer returns where the pointer is in top-left coordinates.
    public var pointer: () -> Point = { Point(x: 0, y: 0) }
    // grab takes the grid keys, the ones a hold of no trigger uses.
    public var grab: (OverlayTrigger) -> Void = { _ in }
    // ungrab lets the grid keys go.
    public var ungrab: () -> Void = {}
    // log is told why a grid did not open.
    public var log: (String) -> Void = { _ in }

    // platform reads the windows and the screens.
    private let platform: Platform
    // anchors holds the choices and the pins.
    private let anchors: Anchors
    // actions works out the area and applies the span.
    private let actions: ActionRunner
    // view draws the grid and takes the mouse on it.
    private let view: any GridView
    // target is the window the grid places, nil while hidden.
    private var target: WindowID?
    // area is the area the grid divides.
    private var area = Frame(x: 0, y: 0, w: 0, h: 0)
    // grid is the picked span.
    private var grid: OverlayGrid?
    // press is where a press on the grid went down, nil when no button is down on it.
    private var press: Point?

    // init builds a grid picker on platform and anchors that applies spans through actions and draws
    // on view, which it gives its mouse handler.
    public init(platform: Platform, anchors: Anchors, actions: ActionRunner, view: any GridView) {
        self.platform = platform
        self.anchors = anchors
        self.actions = actions
        self.view = view
        view.onMouse = { [weak self] phase, p in self?.mouse(phase, p) }
    }

    // showing reports whether the grid is up.
    public var showing: Bool { target != nil }

    // show pops a grid of cols by rows over the area of the window with id window, or of the focused
    // window when nil, and reports whether it opened. Pinned and fullscreen windows get none.
    public func show(cols: Int, rows: Int, window: WindowID?) -> Bool {
        cancel()
        let screens = platform.screens.current()
        let scan = platform.windows.scan(screens, full: true)
        guard let w = window.flatMap({ id in scan.windows.first { $0.id == id } }) ?? scan.focused,
              !anchors.pinned(w), !w.isFullScreen
        else {
            log("grid: no free window in front")
            return false
        }
        let a = actions.area(for: w, screens: screens)
        var start = pointer()
        if start.x < a.x || start.x >= a.x + a.w || start.y < a.y || start.y >= a.y + a.h {
            start = Point(x: w.frame.x + w.frame.w / 2, y: w.frame.y + w.frame.h / 2)
        }
        target = w.id
        area = a
        grid = OverlayGrid(cols: cols, rows: rows, at: start, in: a)
        grab(.none)
        draw()
        return true
    }

    // contains reports whether p, in top-left coordinates, is on the grid.
    public func contains(_ p: Point) -> Bool {
        showing && view.contains(p)
    }

    // cancel puts the grid away without moving anything.
    public func cancel() {
        guard showing else { return }
        target = nil
        grid = nil
        press = nil
        ungrab()
        view.hide()
    }

    // key handles a grabbed key by its tag: move or grow the span, apply it, or cancel.
    public func key(_ tag: String) {
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
    func mouse(_ phase: GridMouse, _ p: Point) {
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
        let f = g.frame(area, gap: anchors.choices.gapPx)
        cancel()
        actions.applyFrame(f, to: id)
    }

    // draw shows the grid with the picked span filled.
    private func draw() {
        guard let g = grid else { return }
        let choices = anchors.choices
        view.show(g, in: area, gap: choices.gapPx, style: choices.snapping.footprint, palette: .harbor)
    }
}
