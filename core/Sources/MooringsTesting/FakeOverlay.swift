import MooringsCore
import MooringsEngine

// FakeOverlay is an OverlayView that records where the footprint was shown.
public final class FakeOverlay: OverlayView {
    // Call is one call the overlay received.
    public enum Call: Equatable, Sendable {
        case show(Frame)
        case hide
    }

    // shown is the frame the footprint covers, nil when hidden.
    public private(set) var shown: Frame?
    // calls records every call in order.
    public private(set) var calls: [Call] = []

    // init builds a hidden overlay.
    public init() {}

    // show records the frame and makes it the shown one.
    public func show(_ frame: Frame, style: FootprintStyle, palette: Palette) {
        calls.append(.show(frame))
        shown = frame
    }

    // hide records the call and clears the shown frame.
    public func hide() {
        calls.append(.hide)
        shown = nil
    }
}
