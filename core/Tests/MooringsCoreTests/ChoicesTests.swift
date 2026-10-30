import Foundation
import Testing

@testable import MooringsCore

// Swift only: a choices file saved before the window actions loads with every new field at its
// default.
@Test func testChoicesOldFileDefaults() {
    let old = Data(#"{"slots":{"left-top":"com.tinyspeck.slackmacgap"},"paused":false}"#.utf8)
    let c = Choices.decode(old).choices
    #expect(c.slots[.leftTop] == "com.tinyspeck.slackmacgap")
    #expect(c.keymap == "rectangle" && c.shortcuts.isEmpty && c.sizes.isEmpty)
    #expect(c.gapPx == 0 && c.ignores.isEmpty && c.snap && c.fullscreenFills && !c.pinFullscreenFills)
}

// Swift only: every window action field survives a save and reload, a removed shortcut included.
@Test func testChoicesActionFieldsRoundTrip() throws {
    var c = Choices()
    c.keymap = "spectacle"
    c.shortcuts = ["maximize": StoredShortcut(mods: ["ctrl", "alt"], key: "k"), "center": nil]
    c.sizes = [
        StoredSize(title: "Reading", x: 0.25, w: 0.5, shortcut: StoredShortcut(mods: ["ctrl", "alt"], key: "9"))
    ]
    c.gapPx = 8
    c.ignores = ["com.apple.Terminal"]
    c.snap = false
    let data = try Choices.encode(c)
    #expect(Choices.decode(data).choices == c)
}

// Swift only: bindings lay the saved shortcuts and sizes over the keymap.
@Test func testBindings() {
    var c = Choices()
    #expect(Bindings(c).map["left-half"]?.text == "⌃⌥←")
    c.shortcuts = ["maximize": StoredShortcut(mods: ["ctrl", "alt"], key: "k"), "center": nil]
    c.sizes = [
        StoredSize(title: "Reading", x: 0.25, w: 0.5, shortcut: StoredShortcut(mods: ["ctrl", "alt"], key: "9"))
    ]
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
    c.workspaces["Desk"] = Workspace(
        name: "Desk", slots: [.leftTop: "com.tinyspeck.slackmacgap"],
        widths: Widths(left: 15, right: 40), heights: nil,
        windows: [
            SavedWindow(
                bundle: "com.apple.Safari", title: "Docs",
                frame: Frame(x: 800, y: 100, w: 900, h: 700))
        ],
        setup: "abc")
    let data = try Choices.encode(c)
    #expect(Choices.decode(data).choices.workspaces == c.workspaces)
}

// Swift only: undo returns every saved frame once and clears them.
@Test func testAnchorsUndo() {
    let anchors = Anchors()
    let w = WindowInfo(
        id: 7, bundle: "com.apple.Safari", frame: Frame(x: 1, y: 2, w: 3, h: 4), onUltrawide: false,
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
    let c = Choices.decode(json).choices
    #expect(c.slots[.leftTop] == "com.tinyspeck.slackmacgap")
    #expect(c.gapPx == 4 && c.ignores == ["com.apple.Terminal"] && c.mouseButtons == ["3": "maximize"])
    #expect(c.behavior == Behaviors())
    #expect(c.buttonClicks.isEmpty)
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
    #expect(Choices.decode(try Choices.encode(c)).choices == c)
}

// Swift only: a behavior object with no fields, or unreadable ones, decodes to the defaults.
@Test func testBehaviorsDecodeEmpty() throws {
    #expect(try JSONDecoder().decode(Behaviors.self, from: Data("{}".utf8)) == Behaviors())
    let bad = Data(#"{"subsequentExecution":"nonsense","stageSize":"wide"}"#.utf8)
    #expect(try JSONDecoder().decode(Behaviors.self, from: bad) == Behaviors())
    #expect(Choices.decode(Data(#"{"behavior":{}}"#.utf8)).choices.behavior.specifiedWidth == 1680)
}

// Swift only: choices with no snapping key load with default snap choices, and an empty object decodes to them.
@Test func testChoicesDecodeWithoutSnapping() throws {
    let c = Choices.decode(Data(#"{"snap":true}"#.utf8)).choices
    #expect(c.snapping == SnapChoices())
    let s = try JSONDecoder().decode(SnapChoices.self, from: Data("{}".utf8))
    #expect(s == SnapChoices())
}

// Swift only: choices saved without slotStacks load with it on, and it round trips.
@Test func testChoicesSlotStacks() throws {
    #expect(Choices.decode(Data(#"{"paused":false}"#.utf8)).choices.slotStacks)
    var c = Choices()
    c.slotStacks = false
    #expect(Choices.decode(try Choices.encode(c)).choices.slotStacks == false)
}

// Swift only: choices with no stacking key load with default stack choices, and an empty object decodes to them.
@Test func testChoicesDecodeWithoutStacking() throws {
    let c = Choices.decode(Data(#"{"snap":true}"#.utf8)).choices
    #expect(c.stacking == StackChoices())
    let s = try JSONDecoder().decode(StackChoices.self, from: Data("{}".utf8))
    #expect(s == StackChoices())
}

// Swift only: choices saved without chains or menu keys load the defaults, and both round trip.
@Test func testChoicesChainsAndMenu() throws {
    let old = Data(#"{"paused":false}"#.utf8)
    let loaded = Choices.decode(old).choices
    #expect(loaded.chains.isEmpty && loaded.menu == MenuChoices())
    var c = Choices()
    c.chains = [Chain(name: "Focus", steps: ["left-half", "maximize"], loops: true)]
    c.menu = MenuChoices()
    c.menu.order = ["maximize", "left-half"]
    c.menu.hidden = ["center"]
    #expect(Choices.decode(try Choices.encode(c)).choices == c)
}

// Swift only: choices saved without appRules load empty, and rules round trip.
@Test func testChoicesAppRules() throws {
    #expect(Choices.decode(Data(#"{"paused":false}"#.utf8)).choices.appRules.isEmpty)
    var c = Choices()
    c.appRules = [AppRule(bundle: "a", action: "left-half"), AppRule(bundle: "b", frame: F(1, 2, 3, 4))]
    #expect(Choices.decode(try Choices.encode(c)).choices == c)
}

// Swift only: restoring defaults resets every preference and keeps the owner's own data.
@Test func testChoicesRestoringDefaults() {
    var c = Choices(
        slots: [.leftTop: "com.apple.Notes"], widths: Widths(left: 20, right: 30), paused: true,
        fullscreenFills: false, pinFullscreenFills: false)
    c.keymap = "spectacle"
    c.shortcuts = ["maximize": StoredShortcut(mods: ["ctrl", "alt"], key: "k")]
    c.gapPx = 8
    c.snap = false
    c.checkUpdates = false
    c.installUpdates = false
    c.mouseButtons = ["3": "maximize"]
    c.buttonClicks = ["red+option": "left-half"]
    c.snapping.footprint.color = "#ff0000"
    c.ignores = ["com.apple.Terminal"]
    c.sizes = [StoredSize(title: "Reading", x: 0.25, w: 0.5, shortcut: nil)]
    c.workspaces = ["Desk": Workspace(name: "Desk")]
    c.chains = [Chain(name: "left-then-max", steps: ["left-half", "maximize-height"])]
    c.appRules = [AppRule(bundle: "com.apple.TextEdit", action: "left-half")]
    var want = Choices(slots: c.slots, widths: c.widths, paused: true)
    want.ignores = c.ignores
    want.sizes = c.sizes
    want.workspaces = c.workspaces
    want.chains = c.chains
    want.appRules = c.appRules
    #expect(c.restoringDefaults() == want)
    #expect(Choices().restoringDefaults() == Choices())
}

// Swift only: renaming a chain moves its shortcut, mouse button, button click and pinned menu entry.
@Test func testChoicesRenameChain() {
    var c = Choices()
    c.chains = [Chain(name: "A", steps: ["left-half"]), Chain(name: "B", steps: ["maximize"])]
    c.shortcuts = ["chain:A": StoredShortcut(mods: ["ctrl", "alt"], key: "k")]
    c.mouseButtons = ["3": "chain:A", "4": "maximize"]
    c.buttonClicks = ["red+option": "chain:A", "green": "maximize"]
    c.menu.order = ["maximize", "chain:A"]
    c.renameChain(at: 0, to: "Focus")
    #expect(c.chains.map(\.name) == ["Focus", "B"])
    #expect(c.shortcuts["chain:A"] == nil)
    #expect(c.shortcuts["chain:Focus"] == .some(StoredShortcut(mods: ["ctrl", "alt"], key: "k")))
    #expect(c.mouseButtons == ["3": "chain:Focus", "4": "maximize"])
    #expect(c.buttonClicks == ["red+option": "chain:Focus", "green": "maximize"])
    #expect(c.menu.order == ["maximize", "chain:Focus"])
    let before = c
    c.renameChain(at: 0, to: "B")
    c.renameChain(at: 5, to: "C")
    #expect(c == before)
}

// Swift only: button clicks survive a save and load.
@Test func testChoicesButtonClicksRoundTrip() throws {
    var c = Choices()
    c.buttonClicks = ["red+option": "left-half", "yellow": "maximize"]
    #expect(Choices.decode(try Choices.encode(c)).choices.buttonClicks == c.buttonClicks)
}

// Swift only: the v1.7.0 choices shape with no profiles decodes with none and no active profile.
@Test func testProfileDecodeOldShape() {
    let json = #"{"slots":{},"paused":false,"keymap":"rectangle","chains":[],"gapPx":4}"#
    let c = Choices.decode(Data(json.utf8)).choices
    #expect(c.profiles.isEmpty)
    #expect(c.activeProfile == nil)
    #expect(c.gapPx == 4)
}

// Swift only: restoring defaults keeps the saved profiles.
@Test func testProfileRestoringDefaultsKeeps() {
    var c = Choices()
    c.profiles = [Profile(name: "Work")]
    #expect(c.restoringDefaults().profiles == c.profiles)
}

// choicesFixture reads the choices v1.13.0 saved, from testdata.
private func choicesFixture() throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("testdata/choices-1.13.0.json")
    return try Data(contentsOf: url)
}

// Swift only: a payload that cannot be read loads the defaults with a reason, and one that can loads
// with none, a field of the wrong type taking its default and keys from a newer version ignored.
@Test func testChoicesDecodeFallback() {
    var kept = Choices()
    kept.paused = true
    let tests: [(In: String, WantFallback: Bool, WantResult: Choices)] = [
        // Test 0: Empty.
        ("", true, Choices()),
        // Test 1: Truncated JSON.
        (#"{"paused":true,"slots":{"left-top":"com.example.a""#, true, Choices()),
        // Test 2: Not an object.
        (#"["paused"]"#, true, Choices()),
        // Test 3: A string where a number goes takes that field's default and keeps the rest.
        (#"{"paused":true,"gapPx":"wide"}"#, false, kept),
        // Test 4: Unknown keys from a newer version are ignored.
        (#"{"paused":true,"futureKey":{"a":[1,2]},"anotherOne":7}"#, false, kept),
        // Test 5: The version 1 shape, slots and paused only.
        (#"{"slots":{},"paused":true}"#, false, kept),
    ]
    for (testNum, test) in tests.enumerated() {
        let got = Choices.decode(Data(test.In.utf8))
        #expect((got.fallback != nil) == test.WantFallback, "test \(testNum): \(got.fallback ?? "none")")
        #expect(got.choices == test.WantResult, "test \(testNum)")
    }
}

// Swift only: the choices v1.13.0 saved decode with no fallback and save back unchanged, with only the
// keys added since then on their defaults.
@Test func testChoicesDecodeV1_13_0() throws {
    let data = try choicesFixture()
    let got = Choices.decode(data)
    #expect(got.fallback == nil, "\(got.fallback ?? "")")
    #expect(got.choices != Choices())
    #expect(got.choices.gapPx == 8 && got.choices.activeProfile == "Work" && got.choices.tiling.mode == .bsp)
    #expect(got.choices.channelCycle && got.choices.installUpdates)
    var saved = String(decoding: try Choices.encode(got.choices), as: UTF8.self)
    for added in [#""channelCycle":true,"#, #""installUpdates":true,"#] {
        #expect(saved.components(separatedBy: added).count == 2, "\(saved)")
        saved = saved.replacingOccurrences(of: added, with: "")
    }
    #expect(saved == String(decoding: data, as: UTF8.self))
}

// Swift only: choices saved without channelCycle load with it on, and it round trips.
@Test func testChoicesChannelCycle() throws {
    #expect(Choices.decode(Data(#"{"paused":false}"#.utf8)).choices.channelCycle)
    var c = Choices()
    c.channelCycle = false
    #expect(Choices.decode(try Choices.encode(c)).choices.channelCycle == false)
}

// Swift only: a choices file written before installUpdates existed loads with it on, and a saved
// false survives a round trip.
@Test func testChoicesInstallUpdates() throws {
    let old = Data(#"{"slots":{},"checkUpdates":false}"#.utf8)
    let c = Choices.decode(old).choices
    #expect(c.installUpdates)
    #expect(!c.checkUpdates)
    var off = Choices()
    off.installUpdates = false
    let back = Choices.decode(try JSONEncoder().encode(off)).choices
    #expect(!back.installUpdates)
}
