import MooringsCore
import MooringsEngine

// FakeGrid is a GridView that records what the grid showed, and lets a test press on it.
public final class FakeGrid: GridView {
    // Call is one call the grid received.
    public enum Call: Equatable, Sendable {
        case show(OverlayGrid, Frame)
        case hide
    }

    // onMouse is told each press, drag and release a test makes on the grid.
    public var onMouse: ((GridMouse, Point) -> Void)?
    // shown is the mark the grid paints, nil when hidden.
    public private(set) var shown: GridMark?
    // calls records every show and hide in order.
    public private(set) var calls: [Call] = []

    // init builds a hidden grid.
    public init() {}

    // show records the grid and area and makes them the shown mark.
    public func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette) {
        calls.append(.show(grid, area))
        shown = GridMark(grid: grid, area: area)
    }

    // hide records the call and clears the shown mark.
    public func hide() {
        calls.append(.hide)
        shown = nil
    }

    // contains reports whether p is inside the shown area.
    public func contains(_ p: Point) -> Bool {
        guard let a = shown?.area else { return false }
        return p.x >= a.x && p.x < a.x + a.w && p.y >= a.y && p.y < a.y + a.h
    }

    // mouse reports phase at p to the handler, as a press, drag or release on the grid would.
    public func mouse(_ phase: GridMouse, at p: Point) {
        onMouse?(phase, p)
    }
}
