import Foundation
import Testing

@testable import MooringsCore

// sinkSteps samples the animation every hundredth of its length.
let sinkSteps = (0...100).map { Double($0) / 100 }

// Test 0: The first frame is the boat at rest, with nothing risen and nothing faded.
@Test func testSinkStart() {
    #expect(
        Sink.pose(0) == SinkPose(reach: 0, flop: 0, grab: 0, depth: 0, tilt: 0, bubbles: 0, fade: 1))
}

// Test 1: The last frame has the boat under, the bubbles up and the scene gone.
@Test func testSinkEnd() {
    let p = Sink.pose(1)
    #expect(p.depth == 1)
    #expect(p.bubbles == 1)
    #expect(p.fade == 0)
    #expect(p.reach == 1)
}

// Test 2: A time outside the animation is clamped to its ends.
@Test func testSinkClamped() {
    #expect(Sink.pose(-1) == Sink.pose(0))
    #expect(Sink.pose(2) == Sink.pose(1))
}

// Test 3: The tentacles have hold of the hull before the boat moves down.
@Test func testSinkGrabFirst() {
    for t in sinkSteps where Sink.pose(t).depth > 0 {
        #expect(Sink.pose(t).reach == 1, "t \(t)")
        #expect(Sink.pose(t).grab == 1, "t \(t)")
    }
}

// Test 7: The tentacles rise slowly, over at least 1 s, while the boat rocks both ways, then lash
// out in at most 0.2 s and drag the boat under in at most 0.4 s.
@Test func testSinkRisesSlowStrikesFast() {
    let span = { (xs: [Double]) in ((xs.max() ?? 0) - (xs.min() ?? 0)) * Sink.seconds }
    let rising = sinkSteps.filter { Sink.pose($0).reach > 0 && Sink.pose($0).reach < 1 }
    #expect(span(rising) >= 1)
    #expect(Set(rising.map { Sink.pose($0).tilt.sign }).count == 2, "the boat rocks both ways")
    #expect(span(sinkSteps.filter { Sink.pose($0).grab > 0 && Sink.pose($0).grab < 1 }) <= 0.2)
    #expect(span(sinkSteps.filter { Sink.pose($0).depth > 0 && Sink.pose($0).depth < 1 }) <= 0.4)
}

// Test 4: The boat only ever goes down.
@Test func testSinkDepthMonotonic() {
    for (a, b) in zip(sinkSteps, sinkSteps.dropFirst()) {
        #expect(Sink.pose(b).depth >= Sink.pose(a).depth, "t \(a) to \(b)")
    }
}

// Test 5: The boat is out of sight before the scene starts to fade.
@Test func testSinkUnderBeforeFade() {
    for t in sinkSteps where Sink.pose(t).fade < 1 {
        #expect(Sink.pose(t).depth == 1, "t \(t)")
    }
}

// Test 6: The boat leans back against the tug before it is pulled under, then leans forward.
@Test func testSinkTug() {
    let before = sinkSteps.filter { Sink.pose($0).depth == 0 }.map { Sink.pose($0).tilt }
    #expect((before.min() ?? 0) < 0)
    #expect(Sink.pose(1).tilt > 0)
}
