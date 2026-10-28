import Testing

@testable import MooringsCore

// TapPressStep is one event the mouse tap sees.
enum TapPressStep: Sendable {
    case down(swallow: Bool)
    case up
    case recover(buttonDown: Bool)
}

// TapPressCase is a run of events and how each one ends a press.
struct TapPressCase: Sendable {
    // Steps is the events in order.
    var Steps: [TapPressStep]
    // WantEnds is what each step returns, one per step.
    var WantEnds: [TapPress.End]
    // WantHeld is whether a press is still open after the last step.
    var WantHeld: Bool
}

// tapPressCases covers each rule of TapPress.
let tapPressCases: [TapPressCase] = [
    // Test 0: A plain click ends plain.
    TapPressCase(Steps: [.down(swallow: false), .up], WantEnds: [.none, .plain], WantHeld: false),
    // Test 1: A swallowed click ends swallowed.
    TapPressCase(Steps: [.down(swallow: true), .up], WantEnds: [.none, .swallowed], WantHeld: false),
    // Test 2: A swallowed press whose release came while the tap was off ends on recovery, so the
    // next click's release is not swallowed.
    TapPressCase(Steps: [.down(swallow: true), .recover(buttonDown: false), .down(swallow: false), .up],
                 WantEnds: [.none, .swallowed, .none, .plain], WantHeld: false),
    // Test 3: A press still held at recovery stays open and ends on its release.
    TapPressCase(Steps: [.down(swallow: true), .recover(buttonDown: true), .up],
                 WantEnds: [.none, .none, .swallowed], WantHeld: false),
    // Test 4: A plain drag whose release was missed ends plain on recovery.
    TapPressCase(Steps: [.down(swallow: false), .recover(buttonDown: false)], WantEnds: [.none, .plain],
                 WantHeld: false),
    // Test 5: A new press after a missed swallowed release reports the old press as swallowed.
    TapPressCase(Steps: [.down(swallow: true), .down(swallow: false), .up],
                 WantEnds: [.none, .swallowed, .plain], WantHeld: false),
    // Test 6: A release with no press seen still reaches the app as a plain click.
    TapPressCase(Steps: [.up], WantEnds: [.plain], WantHeld: false),
    // Test 7: Recovery with nothing held ends nothing.
    TapPressCase(Steps: [.recover(buttonDown: false)], WantEnds: [.none], WantHeld: false),
    // Test 8: A press with no release yet stays held.
    TapPressCase(Steps: [.down(swallow: false)], WantEnds: [.none], WantHeld: true),
]

@Test(arguments: tapPressCases)
func testTapPress(test: TapPressCase) {
    var press = TapPress()
    var ends: [TapPress.End] = []
    for step in test.Steps {
        switch step {
        case let .down(swallow):
            ends.append(press.pressing())
            press.down(swallow: swallow)
        case .up: ends.append(press.up())
        case let .recover(buttonDown): ends.append(press.recover(buttonDown: buttonDown))
        }
    }
    #expect(ends == test.WantEnds)
    #expect(press.held == test.WantHeld)
}
