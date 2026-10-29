import Foundation

// SinkPose is one frame of the quit animation, each part as a share from 0 to 1 except tilt.
public struct SinkPose: Equatable, Sendable {
    // reach is how far the tentacles have risen out of the water beside the boat.
    public var reach: Double
    // flop is how far through their slow sway the tentacles are while they rise.
    public var flop: Double
    // grab is how far the tentacles have moved from swaying free to curled over the hull.
    public var grab: Double
    // depth is how far the boat has been pulled under, 1 being out of sight.
    public var depth: Double
    // tilt is the boat's lean in degrees, positive to the right.
    public var tilt: Double
    // bubbles is how far the bubbles have risen, 0 before the first shows.
    public var bubbles: Double
    // fade is the opacity of the whole scene.
    public var fade: Double
}

// Sink holds the timing of the quit animation: two tentacles rise slowly beside the boat, swaying,
// then lash out over the hull and drag it under fast, bubbles rise, and the scene fades. Every
// function is pure.
public enum Sink {
    // seconds is how long the animation runs before Moorings quits.
    public static let seconds = 2.6
    // riseEnd is when the tentacles are fully up, and grabStart when they lash out, as shares of
    // seconds.
    static let riseEnd = 0.5, grabStart = 0.56
    // rockDegrees is how far the boat rocks, uneasy, while the tentacles rise.
    static let rockDegrees = 2.5
    // tugDegrees is how far the boat leans back as the tentacles take hold.
    static let tugDegrees = -8.0
    // sinkDegrees is how far the boat leans as it goes under.
    static let sinkDegrees = 14.0

    // pose returns the frame at t, the share of seconds gone. A t outside 0...1 is clamped.
    public static func pose(_ t: Double) -> SinkPose {
        let t = min(max(t, 0), 1)
        let flop = ramp(t, 0, grabStart)
        let grab = smooth(ramp(t, grabStart, 0.61))
        let pull = ramp(t, 0.63, 0.75)
        let depth = pull * pull
        let rock = sin(Double.pi * 3 * flop) * sin(Double.pi * flop) * rockDegrees
        let tug = sin(Double.pi * ramp(t, 0.6, 0.65)) * tugDegrees
        return SinkPose(
            reach: smooth(ramp(t, 0.02, riseEnd)), flop: flop, grab: grab,
            depth: depth, tilt: rock + tug + depth * sinkDegrees, bubbles: ramp(t, 0.72, 1),
            fade: 1 - smooth(ramp(t, 0.84, 1)))
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
