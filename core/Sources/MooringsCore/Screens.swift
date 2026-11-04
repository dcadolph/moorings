import Foundation

// Screens holds the attached displays in global top-left coordinates.
public struct Screens: Equatable, Sendable {
    // full lists each screen's full frame.
    public let full: [Frame]
    // usable lists each screen's frame without the menu bar, the Dock, or the taskbar.
    public let usable: [Frame]
    // host is the index of the display moorings anchors on, nil when none is attached.
    public let host: Int?
    // isUltrawide reports whether the host is an ultrawide.
    public let isUltrawide: Bool

    // init builds the displays from their full and usable frames, in the same order.
    public init(full: [Frame], usable: [Frame], host: Int?, isUltrawide: Bool) {
        self.full = full
        self.usable = usable
        self.host = host
        self.isUltrawide = isUltrawide
    }

    // hostFrame returns the host's usable frame, nil when no display is attached.
    public var hostFrame: Frame? { host.map { usable[$0] } }

    // index returns the screen f overlaps most, nil when it overlaps none.
    public func index(_ f: Frame) -> Int? {
        var best: Int?
        var bestArea = 0.0
        for (i, s) in full.enumerated() {
            let w = min(f.x + f.w, s.x + s.w) - max(f.x, s.x)
            let h = min(f.y + f.h, s.y + s.h) - max(f.y, s.y)
            if w > 0, h > 0, w * h > bestArea {
                best = i
                bestArea = w * h
            }
        }
        return best
    }
}
