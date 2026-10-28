import Testing

@testable import MooringsCore

// ScreensIndexCase is one Screens.index expectation.
struct ScreensIndexCase: Sendable, CustomTestStringConvertible {
    // Name labels the case.
    let name: String
    // Frame is the window frame asked about.
    let frame: Frame
    // WantIndex is the screen it overlaps most, nil when none.
    let wantIndex: Int?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// screensPair is a 1920 wide screen with a 5120 ultrawide to its right.
let screensPair = Screens(
    full: [Frame(x: 0, y: 0, w: 1920, h: 1080), Frame(x: 1920, y: 0, w: 5120, h: 1440)],
    usable: [Frame(x: 0, y: 0, w: 1920, h: 1032), Frame(x: 1920, y: 0, w: 5120, h: 1392)],
    ultrawide: 1
)

// screensIndexCases covers the overlap rule.
let screensIndexCases: [ScreensIndexCase] = [
    ScreensIndexCase(name: "inside the first", frame: Frame(x: 100, y: 100, w: 800, h: 600),
                     wantIndex: 0), // Test 0: Inside the first screen.
    ScreensIndexCase(name: "inside the ultrawide", frame: Frame(x: 3000, y: 100, w: 800, h: 600),
                     wantIndex: 1), // Test 1: Inside the ultrawide.
    ScreensIndexCase(name: "mostly on the ultrawide", frame: Frame(x: 1820, y: 100, w: 800, h: 600),
                     wantIndex: 1), // Test 2: Straddles, more on the ultrawide.
    ScreensIndexCase(name: "mostly on the first", frame: Frame(x: 1320, y: 100, w: 800, h: 600),
                     wantIndex: 0), // Test 3: Straddles, more on the first screen.
    ScreensIndexCase(name: "off every screen", frame: Frame(x: -900, y: 100, w: 800, h: 600),
                     wantIndex: nil), // Test 4: Off every screen.
    ScreensIndexCase(name: "touching an edge", frame: Frame(x: 7040, y: 0, w: 100, h: 100),
                     wantIndex: nil), // Test 5: Touches the right edge only.
]

// testScreensIndex checks that a frame belongs to the screen it overlaps most.
@Test(arguments: screensIndexCases)
func testScreensIndex(test: ScreensIndexCase) {
    #expect(screensPair.index(test.frame) == test.wantIndex)
}

// testScreensWide checks that wide is the ultrawide's usable frame and nil without one.
@Test func testScreensWide() {
    #expect(screensPair.wide == Frame(x: 1920, y: 0, w: 5120, h: 1392))
    let none = Screens(full: screensPair.full, usable: screensPair.usable, ultrawide: nil)
    #expect(none.wide == nil)
}
