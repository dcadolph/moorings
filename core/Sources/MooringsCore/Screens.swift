import Foundation

// Screens holds the attached displays in global top-left coordinates.
public struct Screens: Equatable, Sendable {
    // full lists each screen's full frame.
    public let full: [Frame]
    // usable lists each screen's frame without the menu bar, the Dock, or the taskbar.
    public let usable: [Frame]
    // ultrawide is the index of the ultrawide, nil when none is attached.
    public let ultrawide: Int?

    // init builds the displays from their full and usable frames, in the same order.
    public init(full: [Frame], usable: [Frame], ultrawide: Int?) {
        self.full = full
        self.usable = usable
        self.ultrawide = ultrawide
    }

    // wide returns the ultrawide's usable frame, nil when none is attached.
    public var wide: Frame? { ultrawide.map { usable[$0] } }

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
