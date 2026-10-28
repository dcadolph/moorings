import AppKit

import MooringsCore
import MooringsEngine

// GridPanel is the Mac GridView: the borderless panel that draws the keyboard grid over an area, with
// the picked span filled. A panel with a mouse handler takes clicks and drags on the grid without
// bringing Moorings forward; one without lets every click through.
@MainActor
final class GridPanel {
    // panel is the grid window, nil while hidden.
    private var panel: NSPanel?
    // view draws the cells.
    private let view = GridCells()
    // shown is the mark the grid paints, nil when hidden.
    private(set) var shown: GridMark?

    // onMouse is told each press, drag and release on the grid, nil when the grid lets clicks through.
    var onMouse: ((GridMouse, Point) -> Void)? {
        get { view.onMouse }
        set { view.onMouse = newValue }
    }

    // contains reports whether p, in global top-left coordinates, is on the shown grid.
    func contains(_ p: Point) -> Bool {
        guard let panel else { return false }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return panel.frame.contains(CGPoint(x: p.x, y: primary - p.y))
    }

    // show draws grid over area, in global top-left coordinates, in style's colors on palette.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette) {
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
        shown = GridMark(grid: grid, area: area)
    }

    // hide removes the grid.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        shown = nil
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

// GridPanel is the Mac GridView.
extension GridPanel: @preconcurrency GridView {}

// GridCells draws the grid's cell outlines and fills the picked span, and reports the mouse on it when
// it has a handler.
final class GridCells: NSView {
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
