import MooringsCore

// OverlayView paints the footprint that shows where a window will land.
public protocol OverlayView: AnyObject {
    // show paints the footprint at frame; a second show moves it.
    func show(_ frame: Frame, style: FootprintStyle, palette: Palette)
    // hide takes the footprint off screen.
    func hide()
    // shown is the frame the footprint covers, nil when hidden.
    var shown: Frame? { get }
}
