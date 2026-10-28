import Testing

@testable import MooringsCore

// WidthsCase is one width resolution expectation.
struct WidthsCase: Sendable, CustomTestStringConvertible {
    // Saved is the saved choice.
    let saved: Widths?
    // Config is the configured pair.
    let config: Widths?
    // WantWidths is the expected pair in effect.
    let wantWidths: Widths
    // WantWarning reports whether a fallback warning is expected.
    let wantWarning: Bool

    // testDescription labels the case in test output.
    var testDescription: String { "saved \(String(describing: saved)) config \(String(describing: config))" }
}

// widthsCases mirrors anchors_test.lua tests 26 and 63.
let widthsCases: [WidthsCase] = [
    // Test 0: Config.
    WidthsCase(saved: nil, config: Widths(left: 10, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: false),
    // Test 1: Saved wins.
    WidthsCase(saved: Widths(left: 15, right: 30), config: Widths(left: 10, right: 45), wantWidths: Widths(left: 15, right: 30), wantWarning: false),
    // Test 2: No channel.
    WidthsCase(saved: nil, config: Widths(left: 50, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: true),
    // Test 3: Bad saved.
    WidthsCase(saved: Widths(left: 60, right: 45), config: Widths(left: 10, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: false),
    // Test 4: Channel at 10.
    WidthsCase(saved: Widths(left: 45, right: 45), config: nil, wantWidths: Widths(left: 45, right: 45), wantWarning: false),
    // Test 5: Zero strip.
    WidthsCase(saved: Widths(left: 0, right: 45), config: nil, wantWidths: Widths(left: 10, right: 45), wantWarning: true),
]

// testWidths checks which width pair wins.
@Test(arguments: widthsCases)
func testWidths(test: WidthsCase) {
    let (got, warning) = Layout.widths(saved: test.saved, config: test.config)
    #expect(got == test.wantWidths)
    #expect((warning != nil) == test.wantWarning)
}

// Test 6: Every preset leaves a usable channel.
@Test func testPresetsValid() {
    for preset in Layout.presets {
        #expect(Layout.validSplit(preset), "\(preset)")
    }
}

// SteppedCase is one width stepper expectation.
struct SteppedCase: Sendable, CustomTestStringConvertible {
    // Start is the pair before the step.
    let start: Widths
    // Side is the side stepped.
    let side: Side
    // Delta is the step.
    let delta: Double
    // MinPoints is the learned minimum width of the side's pin.
    let minPoints: Double
    // WantWidths is the expected pair after the step.
    let wantWidths: Widths
    // WantOK reports whether the step is allowed.
    let wantOK: Bool

    // testDescription labels the case in test output.
    var testDescription: String { "\(side) \(delta) from \(start)" }
}

// steppedCases mirrors anchors_test.lua tests 58, 60, 61 and 168.
let steppedCases: [SteppedCase] = [
    // Test 0: Left wider.
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: 1, minPoints: 0, wantWidths: Widths(left: 11, right: 45), wantOK: true),
    // Test 1: Right narrower.
    SteppedCase(start: Widths(left: 10, right: 45), side: .right, delta: -1, minPoints: 0, wantWidths: Widths(left: 10, right: 44), wantOK: true),
    // Test 2: Channel floor.
    SteppedCase(start: Widths(left: 45, right: 45), side: .left, delta: 1, minPoints: 0, wantWidths: Widths(left: 46, right: 45), wantOK: false),
    // Test 3: Narrower allowed.
    SteppedCase(start: Widths(left: 45, right: 45), side: .left, delta: -1, minPoints: 0, wantWidths: Widths(left: 44, right: 45), wantOK: true),
    // Test 4: Strip at zero.
    SteppedCase(start: Widths(left: 1, right: 45), side: .left, delta: -1, minPoints: 0, wantWidths: Widths(left: 0, right: 45), wantOK: false),
    // Test 5: Held open.
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: -1, minPoints: 500, wantWidths: Widths(left: 9, right: 45), wantOK: false),
    // Test 6: Wider past a hold.
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: 1, minPoints: 600, wantWidths: Widths(left: 11, right: 45), wantOK: true),
]

// testStepped checks the width steppers on the 5120 point ultrawide.
@Test(arguments: steppedCases)
func testStepped(test: SteppedCase) {
    let (got, ok) = Layout.stepped(test.start, test.side, test.delta, minPoints: test.minPoints, screenWidth: 5120)
    #expect(got == test.wantWidths)
    #expect(ok == test.wantOK)
}

// HeightsCase is one height resolution expectation.
struct HeightsCase: Sendable, CustomTestStringConvertible {
    // Saved is the saved choice.
    let saved: PartialHeights
    // Config is the configured pair.
    let config: PartialHeights
    // WantHeights is the expected pair in effect.
    let wantHeights: Heights
    // WantWarnings is the expected warning count.
    let wantWarnings: Int

    // testDescription labels the case in test output.
    var testDescription: String { "saved \(saved) config \(config)" }
}

// heightsCases mirrors anchors_test.lua tests 153, 156 and 157.
let heightsCases: [HeightsCase] = [
    // Test 0: Even.
    HeightsCase(saved: PartialHeights(), config: PartialHeights(), wantHeights: Heights(left: 50, right: 50), wantWarnings: 0),
    // Test 1: Bad right.
    HeightsCase(saved: PartialHeights(), config: PartialHeights(left: 25, right: 95), wantHeights: Heights(left: 25, right: 50), wantWarnings: 1),
    // Test 2: Choice wins.
    HeightsCase(saved: PartialHeights(left: 75), config: PartialHeights(left: 25), wantHeights: Heights(left: 75, right: 50), wantWarnings: 0),
    // Test 3: Partial.
    HeightsCase(saved: PartialHeights(left: 20), config: PartialHeights(right: 30), wantHeights: Heights(left: 20, right: 30), wantWarnings: 0),
    // Test 4: Bad saved.
    HeightsCase(saved: PartialHeights(left: 5), config: PartialHeights(right: 30), wantHeights: Heights(left: 50, right: 30), wantWarnings: 0),
]

// testHeights checks which top row heights win, side by side.
@Test(arguments: heightsCases)
func testHeights(test: HeightsCase) {
    let (got, warnings) = Layout.heights(saved: test.saved, config: test.config)
    #expect(got == test.wantHeights)
    #expect(warnings.count == test.wantWarnings)
}

// Test 5: A junk configured height, set but not a number, warns and falls back to 50.
@Test func testHeightsJunkConfig() {
    let (got, warnings) = Layout.heights(saved: PartialHeights(), config: PartialHeights(), configSet: [.left])
    #expect(got == Heights(left: 50, right: 50))
    #expect(warnings == ["leftTopPct must be a number from 10 to 90: using 50"])
}

// Test 6: The height steppers move by five and stop with either row at 10, mirroring test 155.
@Test func testTopStepped() {
    #expect(Layout.topStepped(Heights(left: 50, right: 50), .left, Layout.heightStep) == (55, true))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .left, 5) == (95, false))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .right, -5) == (5, false))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .right, 5) == (15, true))
}

// UltrawideCase is one screen choice expectation.
struct UltrawideCase: Sendable, CustomTestStringConvertible {
    // Screens are the full frames.
    let screens: [Frame]
    // WantIndex is the expected ultrawide, nil for none.
    let wantIndex: Int?

    // testDescription labels the case in test output.
    var testDescription: String { "\(screens)" }
}

// ultrawideCases mirrors anchors_test.lua test 27 and the screens seen in the step 0 spike.
let ultrawideCases: [UltrawideCase] = [
    // Test 0: Widest wins.
    UltrawideCase(screens: [F(0, 0, 3440, 1440), F(3440, 0, 5120, 1440)], wantIndex: 1),
    // Test 1: This desk.
    UltrawideCase(screens: [F(0, 0, 5120, 1440), F(5120, -1021, 1920, 1080)], wantIndex: 0),
    // Test 2: Laptop only.
    UltrawideCase(screens: [F(0, 0, 1512, 982)], wantIndex: nil),
    // Test 3: No screens.
    UltrawideCase(screens: [], wantIndex: nil),
]

// testUltrawide checks which screen counts as the ultrawide.
@Test(arguments: ultrawideCases)
func testUltrawide(test: UltrawideCase) {
    #expect(Layout.ultrawide(test.screens) == test.wantIndex)
}

// ClampedCase is one typed strip width expectation.
struct ClampedCase: Sendable, CustomTestStringConvertible {
    // Start is the pair before the edit.
    let start: Widths
    // Side is the side edited.
    let side: Side
    // Pct is the typed percent.
    let pct: Double
    // MinPoints is the learned minimum width of the side's pin.
    let minPoints: Double
    // WantWidths is the expected pair after the edit.
    let wantWidths: Widths
    // WantRange is the expected range for the side before the edit.
    let wantRange: ClosedRange<Double>

    // testDescription labels the case in test output.
    var testDescription: String { "\(side) to \(pct) from \(start)" }
}

// clampedCases runs on the 5120 point ultrawide.
let clampedCases: [ClampedCase] = [
    // Test 0: In range.
    ClampedCase(start: Widths(left: 10, right: 45), side: .left, pct: 20, minPoints: 0, wantWidths: Widths(left: 20, right: 45), wantRange: 1...45),
    // Test 1: Channel ceiling.
    ClampedCase(start: Widths(left: 10, right: 45), side: .left, pct: 70, minPoints: 0, wantWidths: Widths(left: 45, right: 45), wantRange: 1...45),
    // Test 2: Floor of one.
    ClampedCase(start: Widths(left: 10, right: 45), side: .right, pct: 0, minPoints: 0, wantWidths: Widths(left: 10, right: 1), wantRange: 1...80),
    // Test 3: App floor rounds up.
    ClampedCase(start: Widths(left: 13, right: 45), side: .left, pct: 8, minPoints: 668, wantWidths: Widths(left: 14, right: 45), wantRange: 14...45),
    // Test 4: Whole percent.
    ClampedCase(start: Widths(left: 10, right: 45), side: .left, pct: 12.4, minPoints: 0, wantWidths: Widths(left: 12, right: 45), wantRange: 1...45),
    // Test 5: App wider than room.
    ClampedCase(start: Widths(left: 10, right: 85), side: .left, pct: 10, minPoints: 1000, wantWidths: Widths(left: 5, right: 85), wantRange: 5...5),
]

// testClamped checks the typed widths and the range each side may take.
@Test(arguments: clampedCases)
func testClamped(test: ClampedCase) {
    let r = Layout.widthRange(test.start, test.side, minPoints: test.minPoints, screenWidth: 5120)
    #expect(r == test.wantRange)
    let got = Layout.clamped(test.start, test.side, test.pct, minPoints: test.minPoints, screenWidth: 5120)
    #expect(got == test.wantWidths)
    #expect(Layout.validSplit(got))
}

// Test 7: Typed row heights stay inside the row minimum and round to a whole percent.
@Test func testClampedTop() {
    #expect(Layout.clampedTop(3) == Layout.minRowPct)
    #expect(Layout.clampedTop(97) == 100 - Layout.minRowPct)
    #expect(Layout.clampedTop(33.4) == 33)
}

// Test 8: Points round down, so a strip never claims a point it does not cover.
@Test func testPoints() {
    #expect(Layout.points(13, screenWidth: 5120) == 665)
    #expect(Layout.points(0, screenWidth: 5120) == 0)
}

// Test 9: The built-in presets differ by at least five points on some side.
@Test func testPresetsSpaced() {
    for (i, a) in Layout.presets.enumerated() {
        for b in Layout.presets.dropFirst(i + 1) {
            #expect(max(abs(a.left - b.left), abs(a.right - b.right)) >= 5, "\(a) \(b)")
        }
    }
}
