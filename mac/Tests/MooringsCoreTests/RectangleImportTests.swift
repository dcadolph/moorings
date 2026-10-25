import Foundation
import Testing

@testable import MooringsCore

// rectangleFixture reads the Rectangle export in testdata.
private func rectangleFixture() throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("testdata/RectangleConfig.json")
    return try Data(contentsOf: url)
}

// Swift only: a full export lands its shortcuts and every mapped default.
@Test func testRectangleImportRoundTrip() throws {
    let (c, warnings) = try RectangleImport.apply(try rectangleFixture(), to: Choices())
    #expect(c.shortcuts["left-half"] == .some(StoredShortcut(mods: ["ctrl", "alt"], key: "left")))
    #expect(c.shortcuts["bottom-half"] == .some(StoredShortcut(mods: ["ctrl", "alt"], key: "down")))
    #expect(c.shortcuts["maximize"] == .some(StoredShortcut(mods: ["ctrl", "alt"], key: "return")))
    #expect(c.shortcuts["first-two-thirds"] == .some(StoredShortcut(mods: ["ctrl", "alt", "cmd"], key: "d")))
    #expect(c.behavior.subsequentExecution == .switchSides)
    #expect(c.behavior.repeatedMaximizeRestores)
    #expect(c.behavior.centerHalfCycles)
    #expect(c.behavior.halvesPreserveOtherAxis)
    #expect(c.behavior.minimumWindowWidth == 0.3)
    #expect(c.behavior.screenEdgeGapTop == 12)
    #expect(c.behavior.screenEdgeGapTopNotch == 20)
    #expect(!c.behavior.applyGapsToMaximize)
    #expect(!c.behavior.unsnapRestore)
    #expect(c.behavior.doubleClickTitleBar)
    #expect(c.behavior.doubleClickIgnoredApps == ["com.apple.Terminal"])
    #expect(c.behavior.moveCursor)
    #expect(c.behavior.enhancedUI == .disableOnly)
    #expect(c.behavior.screensOrderedByX == .minX)
    #expect(c.gapPx == 8)
    #expect(!c.snap)
    #expect(c.snapping.edgeMarginTop == 9)
    #expect(c.snapping.cornerSize == 24)
    #expect(c.snapping.ignoredSnapAreas == ["top", "top-left"])
    #expect(c.snapping.snapModifiers == ["control", "option"])
    #expect(c.snapping.footprint.alpha == 0.45)
    #expect(c.snapping.footprint.borderWidth == 3)
    #expect(c.snapping.footprint.fade)
    #expect(c.snapping.footprint.color == "#FF8000")
    #expect(c.stacking.overlapOffset)
    #expect(c.stacking.overlapOffsetSize == 14)
    #expect(c.stacking.overlapMaxCascade == 3)
    #expect(!c.stacking.badge)
    #expect(!warnings.isEmpty)
}

// Swift only: a shortcut with all four modifiers maps each bit to its moorings modifier.
@Test func testRectangleImportEveryModifier() {
    let flags: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
    let (c, warnings) = RectangleImport.apply(
        shortcuts: ["leftHalf": (keyCode: 123, modifierFlags: flags)], defaults: [:], to: Choices())
    #expect(c.shortcuts["left-half"] == .some(StoredShortcut(mods: ["ctrl", "alt", "shift", "cmd"], key: "left")))
    #expect(warnings.isEmpty)
}

// Swift only: an unknown action and an unknown default become warnings and change nothing.
@Test func testRectangleImportWarnings() throws {
    let (c, warnings) = try RectangleImport.apply(try rectangleFixture(), to: Choices())
    #expect(c.shortcuts["teleport-window"] == nil)
    #expect(warnings.contains { $0.contains("teleportWindow") })
    #expect(warnings.contains { $0.contains("reflowTodo") })
    #expect(warnings.contains { $0.contains("launchOnLogin") })
    #expect(warnings.contains { $0.contains("lastVersion") })
    #expect(warnings.contains { $0.contains("SUEnableAutomaticChecks") })
}

// Swift only: an export unbinds every keymap action it leaves out or marks with key code -1, as
// Rectangle's import does, while the live domain path adds only what it is given.
@Test func testRectangleImportUnbound() throws {
    var start = Choices()
    start.shortcuts["previous-display"] = .some(StoredShortcut(mods: ["cmd"], key: "p"))
    let (c, _) = try RectangleImport.apply(try rectangleFixture(), to: start)
    #expect(c.shortcuts["previous-display"] == .some(nil))
    #expect(c.shortcuts["top-half"] == .some(nil))
    #expect(c.shortcuts["restore"] == .some(nil))
    let b = Bindings(c)
    #expect(b.map["top-half"] == nil)
    #expect(b.map["previous-display"] == nil)
    #expect(b.map["left-half"]?.text == "⌃⌥←")
    let (d, w) = RectangleImport.apply(
        shortcuts: ["previousDisplay": (keyCode: -1, modifierFlags: 0)], defaults: [:], to: Choices())
    #expect(d.shortcuts.isEmpty)
    #expect(w.isEmpty)
}

// Swift only: Rectangle's recommended switch picks the Rectangle keymap and off picks Spectacle's.
@Test func testRectangleImportKeymap() {
    let (off, _) = RectangleImport.apply(shortcuts: [:], defaults: ["alternateDefaultShortcuts": .bool(false)],
                                         to: Choices())
    #expect(off.keymap == "spectacle")
    var start = Choices()
    start.keymap = "magnet"
    let (on, _) = RectangleImport.apply(shortcuts: [:], defaults: ["alternateDefaultShortcuts": .bool(true)],
                                        to: start)
    #expect(on.keymap == "rectangle")
}

// Swift only: an unmapped key code is a warning, not a shortcut.
@Test func testRectangleImportUnknownKeyCode() {
    let (c, w) = RectangleImport.apply(
        shortcuts: ["leftHalf": (keyCode: 82, modifierFlags: 1 << 18)], defaults: [:], to: Choices())
    #expect(c.shortcuts.isEmpty)
    #expect(w.count == 1)
}

// Swift only: the alias names set a half only when its primary name is unbound.
@Test func testRectangleImportAlias() {
    let (c, _) = RectangleImport.apply(
        shortcuts: ["leftSide": (keyCode: 0, modifierFlags: 1 << 18)], defaults: [:], to: Choices())
    #expect(c.shortcuts["left-half"] == .some(StoredShortcut(mods: ["ctrl"], key: "a")))
    let (d, _) = RectangleImport.apply(
        shortcuts: ["leftSide": (keyCode: 0, modifierFlags: 1 << 18),
                    "leftHalf": (keyCode: 1, modifierFlags: 1 << 18)], defaults: [:], to: Choices())
    #expect(d.shortcuts["left-half"] == .some(StoredShortcut(mods: ["ctrl"], key: "s")))
}

// Swift only: empty data and an empty object return the choices unchanged.
@Test func testRectangleImportEmpty() throws {
    var start = Choices()
    start.gapPx = 3
    for text in ["", "  \n", "{}"] {
        let (c, w) = try RectangleImport.apply(Data(text.utf8), to: start)
        #expect(c == start)
        #expect(w.isEmpty)
    }
}

// Swift only: another app's bundle ID and malformed JSON both throw.
@Test func testRectangleImportErrors() {
    #expect(throws: RectangleImportError.wrongApp("com.example.Other")) {
        try RectangleImport.apply(Data(#"{"bundleId":"com.example.Other"}"#.utf8), to: Choices())
    }
    #expect(throws: RectangleImportError.malformed) {
        try RectangleImport.apply(Data("{nope".utf8), to: Choices())
    }
    #expect(throws: Never.self) {
        try RectangleImport.apply(Data(#"{"bundleId":"com.knollsoft.Hookshot"}"#.utf8), to: Choices())
    }
}
