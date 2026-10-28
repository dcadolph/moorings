import Foundation
import Testing

@testable import MooringsCore

// palette builds a palette from hex strings that are known to parse.
private func palette(_ hexes: String...) -> Palette {
    let c = hexes.map { RGB(hex: $0)! }
    return Palette(background: c[0], surface: c[1], text: c[2], muted: c[3], accent: c[4])
}

// Palette case 0: Harbor's text and muted reach 4.5, and its accent reaches 3.0, against both the
// background and the surface.
@Test func testPaletteHarborContrast() {
    let p = Palette.harbor
    for (name, base) in [("background", p.background), ("surface", p.surface)] {
        let text = p.text.contrast(with: base)
        #expect(text >= Palette.textMinimum, "text on \(name): \(text)")
        let muted = p.muted.contrast(with: base)
        #expect(muted >= Palette.textMinimum, "muted on \(name): \(muted)")
        let accent = p.accent.contrast(with: base)
        #expect(accent >= Palette.accentMinimum, "accent on \(name): \(accent)")
    }
}

// Palette case 1: A red accent labels in white and a purple one in black, and both fall back to the
// text color for small accent text.
@Test func testPaletteAccentRules() {
    let red = palette("#0e0c0c", "#1c1919", "#f4f1ee", "#a9a3a0", "#d6282f")
    #expect(red.onAccent == .white)
    #expect(red.accentText == red.text)
    let purple = palette("#140816", "#231027", "#f0e2f5", "#b597bf", "#b04cc8")
    #expect(purple.onAccent == .black)
    #expect(purple.accentText == purple.text)
}

// Palette case 2: A background that reaches 4.5 on the accent labels with the background, and an
// accent that passes as small text keeps it. Harbor's cream accent does both.
@Test func testPaletteOnAccentBackground() {
    let green = palette("#050a05", "#0b160b", "#b8ffb0", "#5fae5a", "#33ff33")
    #expect(green.onAccent == green.background)
    #expect(green.accentText == green.accent)
    #expect(Palette.harbor.onAccent == Palette.harbor.background)
    #expect(Palette.harbor.accentText == Palette.harbor.accent)
}

// Palette case 3: The footprint is the accent at 20% fill and 70% stroke.
@Test func testPaletteFootprint() {
    let p = Palette.harbor
    #expect(p.footprintFill == Tint(color: p.accent, alpha: 0.20))
    #expect(p.footprintStroke == Tint(color: p.accent, alpha: 0.70))
}

// Palette case 4: A hex string parses to its components and a bad one gives nil.
@Test func testRGBHex() {
    #expect(RGB(hex: "#ffffff") == .white)
    #expect(RGB(hex: "000000") == .black)
    #expect(RGB(hex: "#fff") == nil)
    #expect(RGB(hex: "#gggggg") == nil)
}

// Palette case 5: Saved choices and a saved profile from a release with themes still carry a theme
// key, and they decode with it ignored and every other choice kept.
@Test func testPaletteOldThemeKey() throws {
    var c = Choices()
    c.paused = true
    c.gapPx = 6
    let saved = try JSONSerialization.jsonObject(with: try Choices.encode(c)) as! [String: Any]
    var old = saved
    old["theme"] = "rose"
    let got = Choices.decode(try JSONSerialization.data(withJSONObject: old)).choices
    #expect(got.paused)
    #expect(got.gapPx == 6)
    #expect(got == c)

    var s = ProfileSettings()
    s.gapPx = 4
    s.keymap = "spectacle"
    var p = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(s)) as! [String: Any]
    p["theme"] = "grapes"
    let back = try JSONDecoder().decode(ProfileSettings.self, from: try JSONSerialization.data(withJSONObject: p))
    #expect(back.gapPx == 4)
    #expect(back.keymap == "spectacle")
}
