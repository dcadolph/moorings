import Foundation
import Testing

@testable import MooringsCore

// testProfileChoices builds choices with switchable and anchor fields set to something.
private func testProfileChoices(gap: Double = 8) -> Choices {
    var c = Choices(slots: [.leftTop: "com.a"])
    c.gapPx = gap
    c.snap = false
    c.ignores = ["com.ignored"]
    c.chains = [Chain(name: "Focus", steps: ["left-half"])]
    c.mouseButtons = ["2": "maximize"]
    c.workspaces = ["Desk": Workspace(name: "Desk")]
    c.shortcuts["profile:Work"] = StoredShortcut(mods: ["cmd"], key: "w")
    return c
}

// Swift only: snapshot then apply leaves the choices unchanged except the active profile.
@Test func testProfileSnapshotApplyIdentity() {
    let c = testProfileChoices()
    let p = Profile(name: "Work", settings: c.profileSettings())
    var want = c
    want.activeProfile = "Work"
    #expect(c.applying(p) == want)
}

// Swift only: applying changes only the listed fields and leaves anchors and user data alone.
@Test func testProfileApplyTouchesOnlySettings() {
    let base = testProfileChoices(gap: 8)
    var other = Choices(slots: [.rightTop: "com.b"])
    other.gapPx = 20
    other.ignores = ["com.other"]
    let p = Profile(name: "Play", settings: other.profileSettings())
    let got = base.applying(p)
    #expect(got.gapPx == 20)
    #expect(got.chains.isEmpty)
    #expect(got.activeProfile == "Play")
    #expect(got.slots == base.slots)
    #expect(got.widths == base.widths)
    #expect(got.heights == base.heights)
    #expect(got.ignores == base.ignores)
    #expect(got.workspaces == base.workspaces)
    #expect(got.profiles == base.profiles)
    #expect(got.shortcuts.keys.contains("profile:Work"))
}

// Swift only: validation rejects empty and duplicate names and unknown workspaces.
@Test func testProfileValidate() {
    let ok = [Profile(name: "A", workspaces: ["Desk"]), Profile(name: "B")]
    #expect(Profiles.validate(ok, workspaces: ["Desk"]).isEmpty)
    #expect(Profiles.validate([Profile(name: " ")], workspaces: []).count == 1)
    #expect(Profiles.validate([Profile(name: "A"), Profile(name: "A")], workspaces: []).count == 1)
    #expect(Profiles.validate([Profile(name: "A", workspaces: ["Gone"])], workspaces: ["Desk"]).count == 1)
}

// Swift only: renaming a profile moves its shortcut and menu entry and keeps it active.
@Test func testProfileRename() {
    var c = Choices()
    c.profiles = [Profile(name: "Work"), Profile(name: "Play")]
    c.shortcuts["profile:Work"] = StoredShortcut(mods: ["cmd"], key: "w")
    c.menu.order = ["profile:Work"]
    c.activeProfile = "Work"
    c.renameProfile(at: 0, to: "Office")
    #expect(c.profiles[0].name == "Office")
    #expect(c.shortcuts["profile:Work"] == nil)
    #expect(c.shortcuts["profile:Office"] != nil)
    #expect(c.menu.order == ["profile:Office"])
    #expect(c.activeProfile == "Office")
    c.renameProfile(at: 0, to: "Play")
    #expect(c.profiles[0].name == "Office")
}

// Swift only: choices with profiles survive an encode and decode round trip.
@Test func testProfileRoundTrip() throws {
    var c = testProfileChoices()
    c.profiles = [Profile(name: "Work", settings: c.profileSettings(), workspaces: ["Desk"])]
    c.activeProfile = "Work"
    #expect(Choices.decode(try Choices.encode(c)).choices == c)
}

// Swift only: the switch banner names what was recalled, what does not exist and what missed.
@Test func testProfileSwitchMessage() {
    #expect(Profiles.switchMessage(recalled: [], missing: [], missed: 0) == "Switched.")
    #expect(Profiles.switchMessage(recalled: ["A", "B"], missing: [], missed: 0) == "Switched and recalled A, B.")
    #expect(
        Profiles.switchMessage(recalled: [], missing: ["Draft"], missed: 0)
            == "Switched. No workspace is named Draft.")
    #expect(
        Profiles.switchMessage(recalled: ["A"], missing: ["X", "Y"], missed: 0)
            == "Switched and recalled A. No workspaces are named X, Y.")
    #expect(
        Profiles.switchMessage(recalled: ["A"], missing: [], missed: 1)
            == "Switched and recalled A. 1 window had no running app or display.")
    #expect(
        Profiles.switchMessage(recalled: ["A"], missing: [], missed: 3)
            == "Switched and recalled A. 3 windows had no running app or display.")
    #expect(
        Profiles.switchMessage(recalled: [], missing: [], missed: 0, paused: true)
            == "Switched. Workspaces are not recalled while Moorings is paused.")
}
