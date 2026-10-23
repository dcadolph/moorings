import Foundation
import Testing

@testable import MooringsCore

// Swift only: a choices file saved before the window actions loads with every new field at its
// default.
@Test func testChoicesOldFileDefaults() {
    let old = Data(#"{"slots":{"left-top":"com.tinyspeck.slackmacgap"},"paused":false}"#.utf8)
    let c = Choices.decode(old)
    #expect(c.slots[.leftTop] == "com.tinyspeck.slackmacgap")
    #expect(c.keymap == "rectangle" && c.shortcuts.isEmpty && c.sizes.isEmpty)
    #expect(c.gapPx == 0 && c.ignores.isEmpty && c.snap && c.fullscreenFills && c.pinFullscreenFills)
}

// Swift only: every window action field survives a save and reload, a removed shortcut included.
@Test func testChoicesActionFieldsRoundTrip() throws {
    var c = Choices()
    c.keymap = "spectacle"
    c.shortcuts = ["maximize": StoredShortcut(mods: ["ctrl", "alt"], key: "k"), "center": nil]
    c.sizes = [StoredSize(title: "Reading", x: 0.25, w: 0.5, shortcut: StoredShortcut(mods: ["ctrl", "alt"], key: "9"))]
    c.gapPx = 8
    c.ignores = ["com.apple.Terminal"]
    c.snap = false
    let data = try Choices.encode(c)
    #expect(Choices.decode(data) == c)
}

// Swift only: bindings lay the saved shortcuts and sizes over the keymap.
@Test func testBindings() {
    var c = Choices()
    #expect(Bindings(c).map["left-half"]?.text == "⌃⌥←")
    c.shortcuts = ["maximize": StoredShortcut(mods: ["ctrl", "alt"], key: "k"), "center": nil]
    c.sizes = [StoredSize(title: "Reading", x: 0.25, w: 0.5, shortcut: StoredShortcut(mods: ["ctrl", "alt"], key: "9"))]
    let b = Bindings(c)
    #expect(b.map["maximize"]?.key == "k")
    #expect(b.map["center"] == nil)
    #expect(b.map["size:Reading"]?.key == "9")
    #expect(b.specs["size:Reading"] == CustomSpec(x: 0.25, w: 0.5))
    c.keymap = "spectacle"
    c.shortcuts = [:]
    #expect(Bindings(c).map["maximize"]?.text == "⌥⌘F")
    c.keymap = "nonsense"
    #expect(Bindings(c).map["left-half"]?.text == "⌃⌥←")
}
