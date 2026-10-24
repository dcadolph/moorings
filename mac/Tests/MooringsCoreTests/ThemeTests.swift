import Foundation
import Testing

@testable import MooringsCore

// Theme case 0: Every theme's text and muted reach 4.5, and its accent reaches 3.0, against both
// the background and the surface.
@Test(arguments: ThemeName.allCases) func testThemeContrast(_ theme: ThemeName) {
    let p = theme.palette
    for (name, base) in [("background", p.background), ("surface", p.surface)] {
        let text = p.text.contrast(with: base)
        #expect(text >= Palette.textMinimum, "\(theme) text on \(name): \(text)")
        let muted = p.muted.contrast(with: base)
        #expect(muted >= Palette.textMinimum, "\(theme) muted on \(name): \(muted)")
        let accent = p.accent.contrast(with: base)
        #expect(accent >= Palette.accentMinimum, "\(theme) accent on \(name): \(accent)")
    }
}

// Theme case 1: Rose labels an accent fill in white and Tyrian in black, and both fall back to
// the text color for small accent text.
@Test func testThemeAccentRules() {
    let rose = ThemeName.rose.palette
    #expect(rose.onAccent == .white)
    #expect(rose.accentText == rose.text)
    let tyrian = ThemeName.tyrian.palette
    #expect(tyrian.onAccent == .black)
    #expect(tyrian.accentText == tyrian.text)
}

// Theme case 2: A theme whose background reaches 4.5 on the accent labels with the background, and
// a theme whose accent passes as small text keeps it.
@Test func testThemeOnAccentBackground() {
    let neo = ThemeName.neo.palette
    #expect(neo.onAccent == neo.background)
    #expect(neo.accentText == neo.accent)
}

// Theme case 3: The footprint is the accent at 20% fill and 70% stroke.
@Test func testThemeFootprint() {
    let p = ThemeName.dragonfire.palette
    #expect(p.footprintFill == Tint(color: p.accent, alpha: 0.20))
    #expect(p.footprintStroke == Tint(color: p.accent, alpha: 0.70))
}

// Theme case 4: There are twelve themes and every one has a distinct label.
@Test func testThemeList() {
    #expect(ThemeName.allCases.count == 12)
    #expect(Set(ThemeName.allCases.map(\.label)).count == 12)
}

// Theme case 5: A hex string parses to its components and a bad one gives nil.
@Test func testRGBHex() {
    #expect(RGB(hex: "#ffffff") == .white)
    #expect(RGB(hex: "000000") == .black)
    #expect(RGB(hex: "#fff") == nil)
    #expect(RGB(hex: "#gggggg") == nil)
}

// Theme case 6: A saved theme name the app no longer has falls back to Harbor and keeps the other
// choices, so a renamed theme never resets the layout.
@Test func testThemeUnknownName() throws {
    var c = Choices()
    c.paused = true
    c.theme = .rose
    let saved = String(decoding: try Choices.encode(c), as: UTF8.self)
    #expect(saved.contains(#""rose""#))
    let old = Data(saved.replacingOccurrences(of: #""rose""#, with: #""redcoat""#).utf8)
    let got = Choices.decode(old)
    #expect(got.theme == .harbor)
    #expect(got.paused)
}
