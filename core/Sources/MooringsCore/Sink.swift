import Foundation

// SinkPose is one frame of the quit animation, each part as a share from 0 to 1 except tilt.
public struct SinkPose: Equatable, Sendable {
    // water is how far the water has faded in.
    public var water: Double
    // reach is how far the tentacles have risen out of the water and over the hull.
    public var reach: Double
    // depth is how far the boat has been pulled under, 1 being out of sight.
    public var depth: Double
    // tilt is the boat's lean in degrees, positive to the right.
    public var tilt: Double
    // bubbles is how far the bubbles have risen, 0 before the first shows.
    public var bubbles: Double
    // fade is the opacity of the whole scene.
    public var fade: Double
}

// Sink holds the timing of the quit animation: the water comes in, the tentacles rise and grab the
// boat, a tug, the pull under, bubbles, then the scene fades. Every function is pure.
public enum Sink {
    // seconds is how long the animation runs before Moorings quits.
    public static let seconds = 1.3
    // tugDegrees is how far the boat leans back as the tentacles take hold.
    static let tugDegrees = -6.0
    // sinkDegrees is how far the boat leans as it goes under.
    static let sinkDegrees = 14.0

    // pose returns the frame at t, the share of seconds gone. A t outside 0...1 is clamped.
    public static func pose(_ t: Double) -> SinkPose {
        let t = min(max(t, 0), 1)
        let depth = smooth(ramp(t, 0.4, 0.85))
        let tug = sin(Double.pi * ramp(t, 0.3, 0.42)) * tugDegrees
        return SinkPose(
            water: smooth(ramp(t, 0, 0.15)), reach: smooth(ramp(t, 0.1, 0.38)), depth: depth,
            tilt: tug + depth * sinkDegrees, bubbles: ramp(t, 0.6, 1), fade: 1 - smooth(ramp(t, 0.85, 1)))
    }

    // ramp returns where t sits between a and b as a share from 0 to 1.
    static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        min(max((t - a) / (b - a), 0), 1)
    }

    // smooth eases x in and out.
    static func smooth(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }
}
