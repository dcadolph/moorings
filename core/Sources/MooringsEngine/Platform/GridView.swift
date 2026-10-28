import MooringsCore

// GridMark is what a grid overlay shows: the grid with its picked span and the area it divides.
public struct GridMark: Equatable, Sendable {
    // grid is the grid and its picked span.
    public var grid: OverlayGrid
    // area is the area the grid divides.
    public var area: Frame

    // init builds a mark.
    public init(grid: OverlayGrid, area: Frame) {
        self.grid = grid
        self.area = area
    }
}

// GridMouse is what the mouse did on a grid that takes clicks.
public enum GridMouse: Sendable {
    case down, drag, up
}

// GridView paints the cells an area is divided into, with the picked span filled, without taking
// focus. A grid with a mouse handler takes the presses, drags and releases on it; one without lets
// every click through.
public protocol GridView: AnyObject {
    // onMouse is told each press, drag and release on the grid with the pointer in top-left
    // coordinates, nil when the grid lets clicks through. It is set before the first show.
    var onMouse: ((GridMouse, Point) -> Void)? { get set }
    // show paints grid over area with its span inset by gap; a second show repaints it.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette)
    // hide takes the grid off screen.
    func hide()
    // shown is the mark the grid paints, nil when hidden.
    var shown: GridMark? { get }
    // contains reports whether p, in top-left coordinates, is on the shown grid.
    func contains(_ p: Point) -> Bool
}
