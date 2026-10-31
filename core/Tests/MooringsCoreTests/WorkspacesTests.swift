import Foundation
import Testing

@testable import MooringsCore

// Lua case 0: The signature names every screen and ignores their order.
@Test func testWorkspacesSignature() {
    let wide = F(0, 0, 5120, 1440)
    let side = F(5120, 0, 1512, 982)
    let a = Workspaces.signature([wide, side])
    #expect(a == Workspaces.signature([side, wide]))
    #expect(a == "1512x982@5120,0 5120x1440@0,0")
    #expect(a != Workspaces.signature([wide, F(-1512, 0, 1512, 982)]))
    #expect(Workspaces.signature([wide]) != a)
    #expect(Workspaces.signature([]) == "")
}

// Lua case 1: Matching prefers a title match, then any unused window of the app.
@Test func testWorkspacesMatch() {
    let z = F(0, 0, 1, 1)
    let saved = [
        SavedWindow(bundle: "safari", title: "Mail", frame: z),
        SavedWindow(bundle: "safari", title: "Docs", frame: z),
        SavedWindow(bundle: "notes", title: "Notes", frame: z),
        SavedWindow(bundle: "safari", title: "Gone", frame: z),
    ]
    let live = [
        WorkspaceWindow(id: 1, bundle: "safari", title: "Docs", frame: z),
        WorkspaceWindow(id: 2, bundle: "safari", title: "Renamed", frame: z),
        WorkspaceWindow(id: 3, bundle: "chrome", title: "Mail", frame: z),
    ]
    let m = Workspaces.match(saved, live)
    #expect(m[1] == 0)
    #expect(m[0] == 1)
    #expect(m[2] == nil)
    #expect(m[3] == nil)
    let twice = Workspaces.match(
        [SavedWindow(bundle: "a", title: "x", frame: z)],
        [WorkspaceWindow(id: 1, bundle: "b", title: "x", frame: z)])
    #expect(twice[0] == nil)
}

// Lua has no case for fit or the Codable; these cover the ported functions.
@Test func testWorkspacesFitAndCodable() throws {
    let screens = [ScreenAreas(full: F(0, 0, 1000, 800), area: F(0, 25, 1000, 775))]
    #expect(Workspaces.fit(F(800, 600, 300, 300), screens) == F(700, 500, 300, 300))
    #expect(Workspaces.fit(F(2000, 0, 100, 100), screens) == nil)
    let ws = Workspace(
        name: "desk", slots: [.leftTop: "a.b"], widths: Widths(left: 10, right: 45),
        heights: Heights(left: 50, right: 40),
        windows: [SavedWindow(bundle: "a.b", title: "T", frame: F(1, 2, 3, 4))], setup: "sig")
    let back = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(ws))
    #expect(back == ws)
}

// Swift only: a workspace saved without the new keys decodes unchanged, and the new fields round trip.
@Test func testWorkspaceLaunchFieldsDecodeAndRoundTrip() throws {
    let old = Data(#"{"name":"A","windows":[{"bundle":"b","title":"t","frame":{"x":0,"y":0,"w":1,"h":1}}]}"#.utf8)
    let ws = try JSONDecoder().decode(Workspace.self, from: old)
    #expect(ws.recallOnDisplayChange == false)
    #expect(ws.windows[0].launchBundle == nil && ws.windows[0].openTarget == nil)
    var w = ws
    w.recallOnDisplayChange = true
    w.windows[0].launchBundle = "b"
    w.windows[0].openTarget = "https://example.com"
    #expect(try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w)) == w)
}

// Swift only: only unmatched entries with a launch bundle are launched, with their target.
@Test func testWorkspacesLaunches() {
    let z = F(0, 0, 1, 1)
    let ws = Workspace(
        name: "W",
        windows: [
            SavedWindow(bundle: "safari", title: "a", frame: z, launchBundle: "safari", openTarget: "https://x.test"),
            SavedWindow(bundle: "notes", title: "b", frame: z, launchBundle: "notes"),
            SavedWindow(bundle: "mail", title: "c", frame: z),
        ])
    let live = [WorkspaceWindow(id: 1, bundle: "notes", title: "b", frame: z)]
    #expect(Workspaces.launches(ws, live) == [LaunchRequest(bundle: "safari", target: "https://x.test")])
    #expect(Workspaces.launches(ws, []).count == 2)
}

// Swift only: a rule matches its bundle, skips invalid rules and rejects unknown actions.
@Test func testWorkspacesAppRule() {
    let rules = [
        AppRule(bundle: "a", action: "nonsense-action"),
        AppRule(bundle: "a", action: "left-half"),
        AppRule(bundle: "b", frame: F(1, 2, 3, 4)),
        AppRule(bundle: "c", action: "maximize", frame: F(1, 2, 3, 4)),
    ]
    #expect(Workspaces.rule("a", rules)?.action == "left-half")
    #expect(Workspaces.rule("b", rules)?.frame == F(1, 2, 3, 4))
    #expect(Workspaces.rule("c", rules) == nil)
    #expect(Workspaces.rule("d", rules) == nil)
}

// Swift only: recalling returns only the marked workspaces, sorted by name.
@Test func testWorkspacesRecalling() {
    let all = [
        "z": Workspace(name: "Z", recallOnDisplayChange: true),
        "m": Workspace(name: "M"),
        "a": Workspace(name: "A", recallOnDisplayChange: true),
    ]
    #expect(Workspaces.recalling(all).map(\.name) == ["A", "Z"])
}

// A window whose center no screen holds is mapped from the saved setup onto the main screen in
// proportion, and a workspace saved before displays were kept falls back to its windows' span.
@Test func testWorkspacesFitRemapsAGoneDisplay() throws {
    let laptop = ScreenAreas(full: F(0, 0, 1728, 1117), area: F(0, 25, 1728, 1080))
    let wide = F(0, 0, 5120, 1440)
    // Test 0: x 4000 on a 5120 wide setup maps to 1350 on 1728, then the width clamps it.
    #expect(Workspaces.fit(F(4000, 100, 800, 600), [laptop], from: wide) == F(928, 100, 800, 600))
    // Test 1: A narrow window keeps its proportional x.
    #expect(Workspaces.fit(F(4000, 0, 200, 200), [laptop], from: wide) == F(1350, 25, 200, 200))
    // Test 2: A center on a current screen is unchanged by the bounds.
    #expect(Workspaces.fit(F(100, 100, 300, 300), [laptop], from: wide) == F(100, 100, 300, 300))
    // Test 3: No bounds, or empty bounds, leaves it unplaced.
    #expect(Workspaces.fit(F(4000, 100, 800, 600), [laptop]) == nil)
    #expect(Workspaces.fit(F(4000, 100, 800, 600), [laptop], from: F(0, 0, 0, 0)) == nil)
    // Test 4: bounds is the union of the displays, else of the windows.
    let ws = Workspace(
        name: "d", windows: [SavedWindow(bundle: "a", title: "", frame: F(4000, 100, 800, 600))],
        displays: [F(0, 0, 3440, 1440), F(3440, 200, 1920, 1080)])
    #expect(Workspaces.bounds(ws) == F(0, 0, 5360, 1440))
    #expect(Workspaces.bounds(Workspace(name: "d", windows: ws.windows)) == F(4000, 100, 800, 600))
    #expect(Workspaces.bounds(Workspace(name: "d")) == nil)
    // Test 5: displays survive a round trip, and a file without them decodes empty.
    let back = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(ws))
    #expect(back.displays == ws.displays)
    let old = try JSONDecoder().decode(Workspace.self, from: Data(#"{"name":"d"}"#.utf8))
    #expect(old.displays.isEmpty)
}
