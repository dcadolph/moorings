import Testing

@testable import MooringsCore

// bannerRelease is the banner moorings shows when a pinned window is moved by hand.
let bannerRelease = "Click its green button to put it back,\nor press Control-Option-Delete (⌃⌥⌫)."

// Lua case 0: Wrapping keeps newlines, breaks at spaces within 46 characters, and leaves a longer
// word whole.
@Test func testBannerWrap() {
    #expect(Banner.wrap(bannerRelease) == [
        "Click its green button to put it back,",
        "or press Control-Option-Delete (⌃⌥⌫).",
    ])
    let long = Banner.wrap("Windows will not move until Hammerspoon is allowed under Privacy & Security, Accessibility.")
    #expect(long == [
        "Windows will not move until Hammerspoon is",
        "allowed under Privacy & Security,",
        "Accessibility.",
    ])
    for line in long {
        #expect(line.count <= 46)
    }
    let word = String(repeating: "x", count: 60)
    let split = Banner.wrap("a \(word) b")
    #expect(split.count == 3 && split[1] == word)
    #expect(Banner.wrap("") == [""])
    let exact = String(repeating: "y", count: 20) + " " + String(repeating: "z", count: 25)
    #expect(Banner.wrap(exact).count == 1)
    #expect(Banner.wrap(exact + "z").count == 2)
}

// Lua case 1: The box sits 14 points from the right and 10 below the top of the primary screen's
// frame, and grows 16 points per body line.
@Test func testBannerFrame() {
    let screen = Frame(x: 0, y: 25, w: 5120, h: 1415)
    #expect(Banner.frame(lines: 2, screen: screen) == Frame(x: 5120 - 380 - 14, y: 35, w: 380, h: 74))
    #expect(Banner.frame(lines: 1, screen: screen).h == 58)
    #expect(Banner.frame(lines: 3, screen: screen).h == 90)
}

// Lua case 7: Dark mode picks the dark style and anything else the light one. The Lua case's mark
// and canvas checks are drawing and are not ported.
@Test func testBannerStyle() {
    #expect(Banner.style(interfaceStyle: "Dark") == .dark)
    #expect(Banner.style(interfaceStyle: nil) == .light)
}
