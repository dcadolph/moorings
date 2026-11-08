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
    // hostScale is how many of the host's frame units make one point: 1 where frames are in points,
    // and the display's scale where they are in pixels.
    public let hostScale: Double

    // init builds the displays from their full and usable frames, in the same order.
    public init(full: [Frame], usable: [Frame], host: Int?, isUltrawide: Bool, hostScale: Double = 1) {
        self.full = full
        self.usable = usable
        self.host = host
        self.isUltrawide = isUltrawide
        self.hostScale = hostScale
    }

    // init builds the displays from their full and usable frames and picks the host with Layout.host.
    // scales lists each display's frame units per point, in the same order, where they are not points.
    public init(full: [Frame], usable: [Frame], minAspect: Double = Layout.minAspect, scales: [Double] = []) {
        let host = Layout.host(full: full, usable: usable, minAspect: minAspect)
        let scale = host.index.flatMap { scales.indices.contains($0) ? scales[$0] : nil } ?? 1
        self.init(full: full, usable: usable, host: host.index, isUltrawide: host.isUltrawide, hostScale: scale)
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
