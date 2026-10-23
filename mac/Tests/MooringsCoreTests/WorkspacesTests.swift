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
