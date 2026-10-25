import Testing

@testable import MooringsCore

// sc builds a shortcut input from modifier names and a key.
private func sc(_ mods: [String], _ key: String) -> ShortcutInput {
    ShortcutInput(mods: mods, key: key)
}

// has reports whether any problem contains text.
private func has(_ problems: [String], _ text: String) -> Bool {
    problems.contains { $0.contains(text) }
}

// Lua case 0: Labels read as plain words.
@Test func testLabels() {
    #expect(Keymaps.label("left-half") == "Left half")
    #expect(Keymaps.label("top-center-left-eighth") == "Top center left eighth")
    #expect(Keymaps.label("maximize") == "Maximize")
}

// Lua case 1: Shortcut text uses menu glyphs in macOS order.
@Test func testKeyText() {
    #expect(Shortcut(mods: [.ctrl, .alt], key: "left").text == "⌃⌥←")
    #expect(Shortcut(mods: [.cmd, .alt, .ctrl], key: "u").text == "⌃⌥⌘U")
    #expect(Shortcut(mods: [.ctrl, .alt], key: "delete").text == "⌃⌥⌫")
}

// Lua case 2: The keymap alone binds every Rectangle default with no problems.
@Test func testRectangleDefaults() {
    let r = Keymaps.shortcuts()
    #expect(r.map.count == 22)
    #expect(r.problems.isEmpty)
    #expect(r.map["left-half"]?.text == "⌃⌥←")
    #expect(r.map["maximize-height"]?.text == "⌃⌥⇧↑")
    #expect(r.map["next-display"]?.text == "⌃⌥⌘→")
    for name in r.map.keys {
        #expect(Keymaps.known(name), "known \(name)")
    }
}

// Lua case 3: Overrides rebind, unbind, normalize aliases and report bad entries.
@Test func testOverrides() {
    let r = Keymaps.shortcuts([
        "left-half": .set(sc(["command", "Option"], "H")),
        "maximize": .remove,
        "center": .set(sc(["ctrl", "alt"], "k")),
        "sideways": .set(sc(["ctrl"], "s")),
        "top-half": .set(ShortcutInput(key: "t")),
        "bottom-half": .set(sc(["hyper"], "b")),
    ])
    #expect(r.map["left-half"]?.text == "⌥⌘H")
    #expect(r.map["maximize"] == nil)
    #expect(r.map["center"] != nil && r.map["bottom-right"] == nil)
    #expect(has(r.problems, "center and bottom-right share ⌃⌥K: center keeps it"))
    #expect(has(r.problems, "unknown action sideways"))
    #expect(has(r.problems, "shortcut for top-half needs mods and key"))
    #expect(r.map["top-half"] != nil)
    #expect(has(r.problems, "shortcut for bottom-half has an unknown modifier"))
    #expect(r.map["bottom-half"] == nil)
}

// Lua case 4: Special and organize actions are known and an unknown name is not. The family
// listing checks in that case belong to the menu code and are not ported here.
@Test func testKnown() {
    for name in ["larger", "smaller", "restore", "next-display", "previous-display"] {
        #expect(Keymaps.known(name), "special \(name)")
    }
    #expect(!Keymaps.known("sideways"))
    for name in Keymaps.organizeNames {
        #expect(Keymaps.known(name), "organize \(name)")
    }
    for name in Keymaps.windowNames {
        #expect(Keymaps.known(name), "window \(name)")
        #expect(Geometry.position(name, Frame(x: 0, y: 0, w: 100, h: 100)) == nil, "no frame for \(name)")
    }
    #expect(Keymaps.known("workspace:Day"))
    #expect(!Keymaps.known("workspace:"))
    #expect(Keymaps.known("chain:Focus"))
    #expect(!Keymaps.known("chain:"))
    #expect(Keymaps.known(Keymaps.menuName))
    for name in [Actions.specifiedName, "left-side", "center-section"] + Actions.displayNames {
        #expect(Keymaps.known(name), "rectangle \(name)")
    }
    #expect(!Keymaps.known("display-ten"))
}

// Lua case 5: Two config keys on one key keep it for the first in name order, and defaults that
// do not clash stay.
@Test func testSharedKey() {
    let r = Keymaps.shortcuts([
        "center": .set(sc(["ctrl"], "x")),
        "maximize": .set(sc(["ctrl"], "x")),
    ])
    #expect(r.map["center"] != nil && r.map["maximize"] == nil)
    #expect(has(r.problems, "center and maximize share ⌃X: center keeps it"))
    #expect(r.map["left-half"] != nil)
}

// Lua case 6: Valid custom sizes come back with action names and invalid ones are reported. The
// not-a-table check is a type error in Swift and is not ported.
@Test func testSizes() {
    let r = Keymaps.sizes([
        SizeEntry(title: "Reading", x: 0.25, w: 0.5, shortcut: sc(["ctrl", "alt"], "y")),
        SizeEntry(title: "Video", width: 1280, height: 720),
        SizeEntry(x: 0.1),
        SizeEntry(title: "Reading", w: 0.3),
        SizeEntry(title: "Wide", x: 0.5, w: 0.6),
        SizeEntry(title: "Flat", h: 0),
        SizeEntry(title: "Negative", y: -0.1),
        SizeEntry(title: "Tiny", width: 0),
        SizeEntry(title: "Words", w: .other),
        SizeEntry(title: "Thin", w: 0),
    ])
    #expect(r.sizes.count == 2)
    #expect(r.sizes[0].name == "size:Reading" && r.sizes[1].name == "size:Video")
    #expect(r.sizes[0].shortcut?.key == "y" && r.sizes[1].shortcut == nil)
    #expect(r.specs["size:Reading"] == CustomSpec(x: 0.25, y: 0, w: 0.5, h: 1))
    #expect(r.specs["size:Video"] == CustomSpec(width: 1280, height: 720))
    #expect(has(r.problems, "sizes entry 3 needs a title"))
    #expect(has(r.problems, "two entries titled Reading: the first wins"))
    #expect(has(r.problems, "size Wide needs x, y, w and h between 0 and 1"))
    #expect(has(r.problems, "size Flat needs x, y, w and h"))
    #expect(has(r.problems, "size Negative needs x, y, w and h"))
    #expect(has(r.problems, "size Tiny needs a width and height above 0"))
    #expect(has(r.problems, "size Words needs x, y, w and h"))
    #expect(has(r.problems, "size Thin needs x, y, w and h"))
    #expect(r.problems.count == 8)
    #expect(Keymaps.sizes([]).sizes.isEmpty)
    #expect(Keymaps.label("size:Reading") == "Reading")
    #expect(Keymaps.label("chain:Focus") == "Focus")
    #expect(Keymaps.label(Keymaps.menuName) == "Moorings menu at the pointer")
}

// Lua case 7: A custom size shortcut beats a default and a malformed one is reported.
@Test func testSizeShortcuts() {
    let r = Keymaps.shortcuts([:], extra: [
        "size:Reading": .set(sc(["ctrl", "alt"], "c")),
        "size:Bad": .set(ShortcutInput(key: "b")),
    ])
    #expect(r.map["size:Reading"] != nil && r.map["center"] == nil)
    #expect(has(r.problems, "size:Reading and center share ⌃⌥C: size:Reading keeps it"))
    #expect(has(r.problems, "shortcut for size:Bad needs mods and key"))
    let k = Keymaps.shortcuts(["size:Plain": .set(sc(["ctrl"], "p"))], extra: ["size:Plain": .remove])
    #expect(k.map["size:Plain"] != nil && k.problems.isEmpty)
}

// Lua case 8: Spectacle's keymap binds its defaults, and an unknown keymap falls back to
// Rectangle's.
@Test func testSpectacle() {
    let r = Keymaps.shortcuts(keymap: .spectacle)
    #expect(r.map.count == 17)
    #expect(r.problems.isEmpty)
    #expect(r.map["left-half"]?.text == "⌥⌘←")
    #expect(r.map["first-third"]?.text == "⌃⌥→")
    #expect(r.map["last-third"]?.text == "⌃⌥←")
    #expect(r.map["bottom-left"]?.text == "⌃⇧⌘←")
    #expect(r.map["restore"]?.text == "⌥⌘Z")
    #expect(r.map["larger"]?.text == "⌃⌥⇧→")
    for name in r.map.keys {
        #expect(Keymaps.known(name), "known \(name)")
    }
    let fallback = Keymaps.shortcuts(keymap: Keymap(rawValue: "nope") ?? .rectangle)
    #expect(fallback.map["left-half"]?.text == "⌃⌥←")
    #expect(Keymap.names == ["rectangle", "spectacle", "magnet", "windows", "none"])
}

// Lua case 10: Shortcuts are spelled out with the names printed on the keys, glyphs after.
@Test func testSpelled() {
    let restore = Shortcut(mods: [.ctrl, .alt], key: "delete")
    #expect(restore.words == "Control-Option-Delete")
    #expect(restore.spelled == "Control-Option-Delete (⌃⌥⌫)")
    let tall = Shortcut(mods: [.ctrl, .alt, .shift, .cmd], key: "up")
    #expect(tall.words == "Control-Option-Shift-Command-Up Arrow")
    #expect(Shortcut(mods: [.cmd], key: "u").words == "Command-U")
    #expect(Shortcut(mods: [.ctrl], key: "escape").words == "Control-Escape")
    #expect(Keymaps.shortcuts(keymap: .rectangle).map["restore"]?.spelled == "Control-Option-Delete (⌃⌥⌫)")
}

// No Lua case: The gap is a whole number of points from 0 to 100, and anything else is 0 with a
// problem. A.gap reads the host in Lua, so it has no case in actions_test.lua.
@Test func testGap() {
    #expect(Keymaps.gap(.absent).points == 0 && Keymaps.gap(.absent).problem == nil)
    #expect(Keymaps.gap(10.7).points == 10)
    #expect(Keymaps.gap(100).problem == nil)
    for bad: ConfigNumber in [-1, 101, .other] {
        let g = Keymaps.gap(bad)
        #expect(g.points == 0)
        #expect(g.problem == "gapPx must be a number from 0 to 100: using 0")
    }
}

// Lua case 9: mouse buttons 2 to 31 bind known actions and custom sizes, and the rest are refused.
@Test func testMouseButtons() {
    let (map, problems) = MouseButtons.valid(["3": "left-half", "4": "size:Reading", "1": "maximize", "5": "nope",
                                              "x": "center"], sizes: ["size:Reading"])
    #expect(map == [3: "left-half", 4: "size:Reading"])
    #expect(problems.count == 3)
    #expect(problems.contains("mouseButtons names unknown action nope for button 5: ignoring it"))
    #expect(problems.contains("mouseButtons has button 1: use a number from 2 to 31"))
}

// No Lua case: Every Magnet action is known and Magnet binds its defaults without problems.
@Test func testMagnet() {
    let r = Keymaps.shortcuts(keymap: .magnet)
    #expect(r.map.count == 18)
    #expect(r.map["larger"] == nil)
    #expect(r.problems.isEmpty)
    #expect(r.map["left-half"]?.text == "⌃⌥←")
    #expect(r.map["restore"]?.text == "⌃⌥⌫")
    #expect(r.map["next-display"]?.text == "⌃⌥⌘→")
    for name in Keymap.magnet.table.keys {
        #expect(Keymaps.known(name), "known \(name)")
    }
}

// No Lua case: No two actions in any keymap share a shortcut.
@Test func testNoDuplicateShortcuts() {
    for keymap in Keymap.allCases {
        var seen: [String: String] = [:]
        for (name, shortcut) in keymap.table {
            if let other = seen[shortcut.text] {
                Issue.record("\(keymap.rawValue): \(other) and \(name) share \(shortcut.text)")
            }
            seen[shortcut.text] = name
        }
    }
}

// No Lua case: The none keymap binds nothing.
@Test func testNoneKeymap() {
    #expect(Keymap.none.table.isEmpty)
    let r = Keymaps.shortcuts(keymap: .none)
    #expect(r.map.isEmpty)
    #expect(r.problems.isEmpty)
}

// Test: Arrow and fill actions are known.
@Test func testKnownArrowAndFill() {
    for name in Actions.arrowNames + Actions.fillNames {
        #expect(Keymaps.known(name), "known \(name)")
    }
    #expect(Actions.arrowNames.count == 4 && Actions.fillNames.count == 2)
}

// Test: The windows keymap binds Control-Option arrows to Arrow mode and keeps the rest of Rectangle.
@Test func testWindowsKeymap() {
    let windows = Keymap.windows.table
    let rectangle = Keymap.rectangle.table
    for dir in ["left", "right", "up", "down"] {
        #expect(windows["arrow-" + dir] == Shortcut(mods: [.ctrl, .alt], key: dir), "arrow-\(dir)")
    }
    for name in ["left-half", "right-half", "top-half", "bottom-half"] {
        #expect(windows[name] == nil, "no \(name)")
        #expect(rectangle[name] != nil, "rectangle keeps \(name)")
    }
    for (name, _) in rectangle where windows[name] == nil {
        #expect(["left-half", "right-half", "top-half", "bottom-half"].contains(name), "missing \(name)")
    }
    for (name, sc) in windows where !name.hasPrefix("arrow-") {
        #expect(rectangle[name] == sc, "same \(name)")
    }
}

// Swift only: known accepts a profile action name and rejects a bare prefix.
@Test func testProfileKnownAction() {
    #expect(Keymaps.known("profile:Work"))
    #expect(!Keymaps.known("profile:"))
}
