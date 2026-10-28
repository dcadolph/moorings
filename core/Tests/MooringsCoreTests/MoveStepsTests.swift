import Testing

@testable import MooringsCore

// MoveStepsCase is one move and the writes it must make.
struct MoveStepsCase: Sendable {
    // From is the window's current frame, nil when it is not known.
    var From: Frame?
    // To is the frame the move asks for.
    var To: Frame
    // WantSteps is the writes the move makes, in order.
    var WantSteps: [MoveStep]
}

// moveStepsCases covers each rule of MoveSteps.steps.
let moveStepsCases: [MoveStepsCase] = [
    // Test 0: No current frame makes all three writes.
    MoveStepsCase(From: nil, To: Frame(x: 0, y: 0, w: 100, h: 100), WantSteps: MoveSteps.full),
    // Test 1: A left half flipped to the right keeps its size, so only the position is written.
    MoveStepsCase(
        From: Frame(x: 0, y: 0, w: 500, h: 800), To: Frame(x: 500, y: 0, w: 500, h: 800),
        WantSteps: [.position]),
    // Test 2: A half stepping to two thirds keeps its origin, so only the size is written.
    MoveStepsCase(
        From: Frame(x: 0, y: 0, w: 500, h: 800), To: Frame(x: 0, y: 0, w: 667, h: 800),
        WantSteps: [.size]),
    // Test 3: A new size and a new origin make all three writes.
    MoveStepsCase(
        From: Frame(x: 0, y: 0, w: 500, h: 800), To: Frame(x: 1000, y: 0, w: 300, h: 400),
        WantSteps: MoveSteps.full),
    // Test 4: A window already at the target makes no write.
    MoveStepsCase(
        From: Frame(x: 10, y: 20, w: 300, h: 400), To: Frame(x: 10, y: 20, w: 300, h: 400),
        WantSteps: []),
    // Test 5: Differences inside half a point count as equal.
    MoveStepsCase(
        From: Frame(x: 0, y: 0, w: 500.4, h: 799.6), To: Frame(x: 500, y: 0, w: 500, h: 800),
        WantSteps: [.position]),
    // Test 6: A size off by one point is a new size.
    MoveStepsCase(
        From: Frame(x: 0, y: 0, w: 499, h: 800), To: Frame(x: 500, y: 0, w: 500, h: 800),
        WantSteps: MoveSteps.full),
    // Test 7: A height change alone with the same origin writes only the size.
    MoveStepsCase(
        From: Frame(x: 0, y: 30, w: 500, h: 800), To: Frame(x: 0, y: 30, w: 500, h: 400),
        WantSteps: [.size]),
]

@Test(arguments: moveStepsCases)
func testMoveSteps(test: MoveStepsCase) {
    #expect(MoveSteps.steps(from: test.From, to: test.To) == test.WantSteps)
}
