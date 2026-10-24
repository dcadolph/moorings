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

// Swift only: a saved workspace survives a save and reload with its slots, widths and windows.
@Test func testChoicesWorkspaceRoundTrip() throws {
    var c = Choices()
    c.workspaces["Desk"] = Workspace(name: "Desk", slots: [.leftTop: "com.tinyspeck.slackmacgap"],
                                     widths: Widths(left: 15, right: 40), heights: nil,
                                     windows: [SavedWindow(bundle: "com.apple.Safari", title: "Docs",
                                                           frame: Frame(x: 800, y: 100, w: 900, h: 700))],
                                     setup: "abc")
    let data = try Choices.encode(c)
    #expect(Choices.decode(data).workspaces == c.workspaces)
}

// Swift only: undo returns every saved frame once and clears them.
@Test func testAnchorsUndo() {
    let anchors = Anchors()
    let w = WindowInfo(id: 7, bundle: "com.apple.Safari", frame: Frame(x: 1, y: 2, w: 3, h: 4), onUltrawide: false,
                       isMain: true)
    #expect(!anchors.canUndo)
    anchors.save(w)
    var moved = w
    moved.frame = Frame(x: 9, y: 9, w: 9, h: 9)
    anchors.save(moved)
    #expect(anchors.canUndo)
    #expect(anchors.undo() == [7: Frame(x: 1, y: 2, w: 3, h: 4)])
    #expect(!anchors.canUndo && anchors.undo().isEmpty)
}

// Swift only: a choices file with the current key set and no behavior field loads with every behavior at its
// default.
@Test func testChoicesDecodeWithoutBehavior() {
    let json = Data(
        #"""
        {"slots":{"left-top":"com.tinyspeck.slackmacgap","right-top":"com.googlecode.iterm2"},
         "widths":{"left":0.2,"right":0.2},"heights":{"left":0.5,"right":0.5},"paused":false,
         "fullscreenFills":true,"pinFullscreenFills":true,"keymap":"rectangle","shortcuts":{},"sizes":[],
         "gapPx":4,"ignores":["com.apple.Terminal"],"snap":true,"theme":"harbor","workspaces":{},
         "checkUpdates":true,"mouseButtons":{"3":"maximize"}}
        """#.utf8)
    let c = Choices.decode(json)
    #expect(c.slots[.leftTop] == "com.tinyspeck.slackmacgap")
    #expect(c.gapPx == 4 && c.ignores == ["com.apple.Terminal"] && c.mouseButtons == ["3": "maximize"])
    #expect(c.behavior == Behaviors())
    #expect(c.behavior.subsequentExecution == .cycleSizes)
    #expect(c.behavior.minimumWindowWidth == 0.25 && c.behavior.minimumWindowHeight == 0.25)
    #expect(c.behavior.screenEdgeGapTopNotch == -1 && c.behavior.stageSize == 190)
    #expect(c.behavior.specifiedWidth == 1680 && c.behavior.specifiedHeight == 1050)
    #expect(c.behavior.unsnapRestore && c.behavior.applyGapsToMaximize)
    #expect(c.behavior.enhancedUI == .automatic && c.behavior.screensOrderedByX == .yThenMinX)
}

// Swift only: changed behaviors survive a save and reload.
@Test func testChoicesBehaviorRoundTrip() throws {
    var c = Choices()
    c.behavior.subsequentExecution = .traverseDisplays
    c.behavior.screenEdgeGapTop = 12
    c.behavior.doubleClickIgnoredApps = ["com.apple.Terminal"]
    c.behavior.enhancedUI = .disableOnly
    #expect(Choices.decode(try Choices.encode(c)) == c)
}

// Swift only: a behavior object with no fields, or unreadable ones, decodes to the defaults.
@Test func testBehaviorsDecodeEmpty() throws {
    #expect(try JSONDecoder().decode(Behaviors.self, from: Data("{}".utf8)) == Behaviors())
    let bad = Data(#"{"subsequentExecution":"nonsense","stageSize":"wide"}"#.utf8)
    #expect(try JSONDecoder().decode(Behaviors.self, from: bad) == Behaviors())
    #expect(Choices.decode(Data(#"{"behavior":{}}"#.utf8)).behavior.specifiedWidth == 1680)
}

// Swift only: choices with no snapping key load with default snap choices, and an empty object decodes to them.
@Test func testChoicesDecodeWithoutSnapping() throws {
    let c = Choices.decode(Data(#"{"snap":true}"#.utf8))
    #expect(c.snapping == SnapChoices())
    let s = try JSONDecoder().decode(SnapChoices.self, from: Data("{}".utf8))
    #expect(s == SnapChoices())
}

// Swift only: choices with no stacking key load with default stack choices, and an empty object decodes to them.
@Test func testChoicesDecodeWithoutStacking() throws {
    let c = Choices.decode(Data(#"{"snap":true}"#.utf8))
    #expect(c.stacking == StackChoices())
    let s = try JSONDecoder().decode(StackChoices.self, from: Data("{}".utf8))
    #expect(s == StackChoices())
}

// Swift only: choices saved without chains or menu keys load the defaults, and both round trip.
@Test func testChoicesChainsAndMenu() throws {
    let old = Data(#"{"paused":false}"#.utf8)
    let loaded = Choices.decode(old)
    #expect(loaded.chains.isEmpty && loaded.menu == MenuChoices())
    var c = Choices()
    c.chains = [Chain(name: "Focus", steps: ["left-half", "maximize"], loops: true)]
    c.menu = MenuChoices()
    c.menu.order = ["maximize", "left-half"]
    c.menu.hidden = ["center"]
    #expect(Choices.decode(try Choices.encode(c)) == c)
}

// Swift only: choices saved without appRules load empty, and rules round trip.
@Test func testChoicesAppRules() throws {
    #expect(Choices.decode(Data(#"{"paused":false}"#.utf8)).appRules.isEmpty)
    var c = Choices()
    c.appRules = [AppRule(bundle: "a", action: "left-half"), AppRule(bundle: "b", frame: F(1, 2, 3, 4))]
    #expect(Choices.decode(try Choices.encode(c)) == c)
}
