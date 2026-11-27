import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// KeeperRig is a workspace keeper on fakes over one 3440x1440 ultrawide with two free pad windows.
final class KeeperRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake display source.
    let screens = FakeScreens.ultrawide()
    // notifier records the banners.
    let notifier = FakeNotifier()
    // clock is the fake clock.
    let clock = FakeClock()
    // store keeps the choices the engine saves.
    let store: FakeStore
    // engine builds the keeper and runs the passes its saves ask for.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // keeper is the keeper under test.
    let keeper: WorkspaceKeeper
    // pads lists the free windows, back to front.
    var pads: [WindowID] = []
    // apps opens the apps a recall asks for, each showing one window.
    let apps: FakeApps

    // init builds the rig with choices changed by edit.
    init(_ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices()
        edit(&c)
        store = FakeStore(c)
        apps = FakeApps(windows: windows, names: ["com.example.mail": "Mail"])
        engine = newTestEngine(
            newTestPlatform(
                windows: windows, screens: screens, clock: clock, notifier: notifier, store: store, apps: apps))
        anchors = engine.anchors
        keeper = engine.workspaces
        pads.append(
            windows.add(bundle: "com.example.pad", frame: Frame(x: 900, y: 200, w: 700, h: 500), title: "one"))
        pads.append(
            windows.add(
                bundle: "com.example.pad", frame: Frame(x: 1700, y: 300, w: 600, h: 400), focus: true, title: "two"))
    }

    // saves counts the times the keeper saved the choices.
    var saves: Int { store.saves }

    // frame returns the window's frame now.
    func frame(_ id: WindowID) -> Frame {
        windows.frame(id) ?? Frame(x: 0, y: 0, w: 0, h: 0)
    }

    // look runs the keeper's after-pass look at the windows on screen.
    func look() {
        let s = screens.current()
        keeper.seen(windows.scan(s, full: true).windows, screens: s)
    }
}

// Test 0: A recall puts each saved window back by title and says so.
@Test func testKeeperSaveRecall() {
    let rig = KeeperRig()
    let before = rig.pads.map(rig.frame)
    rig.keeper.saveWorkspace("desk")
    #expect(rig.anchors.choices.workspaces["desk"]?.windows.map(\.title).sorted() == ["one", "two"])
    rig.windows.nudge(rig.pads[0], to: Frame(x: 100, y: 100, w: 400, h: 300))
    rig.windows.nudge(rig.pads[1], to: Frame(x: 2500, y: 600, w: 500, h: 300))
    #expect(rig.keeper.recall("desk"))
    #expect(rig.pads.map(rig.frame) == before)
    #expect(rig.notifier.notes.last?.title == "Workspace desk" && rig.notifier.notes.last?.body == "Recalled.")
    #expect(rig.saves == 2)
}

// Test 0b: A recall untied from the displays puts a window whose display is gone on the main screen
// where it sat in the saved setup, instead of counting it missed.
@Test func testKeeperRecallRemapsAGoneDisplay() {
    let rig = KeeperRig()
    let saved = rig.screens.current().full
    rig.keeper.saveWorkspace("desk")
    #expect(rig.anchors.choices.workspaces["desk"]?.displays == saved)
    let laptop = Frame(x: 0, y: 25, w: 1200, h: 775)
    rig.screens.screens = Screens(
        full: [Frame(x: 0, y: 0, w: 1200, h: 800)], usable: [laptop], host: nil, isUltrawide: false)
    rig.windows.nudge(rig.pads[1], to: Frame(x: 100, y: 100, w: 500, h: 300))
    #expect(rig.keeper.recall("desk"))
    #expect(rig.notifier.notes.last?.body == "Recalled.")
    let got = rig.frame(rig.pads[1])
    let b = saved[0]
    #expect(abs(got.x - (laptop.x + (1700 - b.x) * laptop.w / b.w)) < 1)
    #expect(got.x >= laptop.x && got.x + got.w <= laptop.x + laptop.w)
    #expect(got.y >= laptop.y && got.y + got.h <= laptop.y + laptop.h)
}

// Test 1: A recall of a name never saved does nothing.
@Test func testKeeperRecallUnknown() {
    let rig = KeeperRig()
    #expect(!rig.keeper.recall("nope"))
    #expect(rig.notifier.notes.isEmpty && rig.saves == 0)
}

// Test 2: Nothing is recalled while paused.
@Test func testKeeperPaused() {
    let rig = KeeperRig()
    rig.keeper.saveWorkspace("desk")
    rig.anchors.choices.paused = true
    #expect(!rig.keeper.recall("desk"))
}

// Test 3: A saved window whose app is not running opens the app, and the pass the recall's save runs
// puts its first window where the workspace saved it, to be checked once more a moment later.
@Test func testKeeperOpensMissingApp() throws {
    let rig = KeeperRig()
    let saved = Frame(x: 1000, y: 400, w: 800, h: 600)
    rig.anchors.choices.workspaces["mail"] = Workspace(
        name: "mail", slots: [:], widths: nil, heights: nil,
        windows: [
            SavedWindow(bundle: "com.example.mail", title: "Inbox", frame: saved, launchBundle: "com.example.mail")
        ],
        setup: nil)
    rig.look()
    #expect(rig.keeper.recall("mail"))
    #expect(rig.apps.opened == ["com.example.mail"])
    #expect(rig.notifier.notes.last?.body == "Recalled. Opening 1 app.")
    let mail = try #require(rig.windows.windows.first { $0.bundle == "com.example.mail" }?.id)
    #expect(rig.frame(mail) == saved)
    #expect(!rig.keeper.waiting)
    #expect(rig.keeper.deadlines() == [rig.clock.now + WorkspaceKeeper.recheckSeconds])
}

// Test 4: A tie follows the display set key, and a burst of display changes recalls the tied
// workspace once, from the last change of the burst after the displays settle.
@Test func testKeeperTieAndDisplayChange() {
    let rig = KeeperRig()
    let office = Screens(
        full: [Frame(x: 0, y: 0, w: 1920, h: 1080)], usable: [Frame(x: 0, y: 25, w: 1920, h: 1055)],
        host: nil, isUltrawide: false)
    rig.screens.screens = office
    rig.keeper.saveWorkspace("desk")
    rig.keeper.tie("desk")
    #expect(rig.keeper.tied("desk"))
    rig.screens.screens = FakeScreens.ultrawide().screens
    #expect(!rig.keeper.tied("desk"))
    rig.screens.screens = office
    rig.keeper.screensChanged()
    rig.clock.advance(by: WorkspaceKeeper.settleSeconds - 0.5)
    rig.keeper.screensChanged()
    rig.clock.advance(by: WorkspaceKeeper.settleSeconds - 0.5)
    #expect(rig.notifier.notes.isEmpty, "a change superseded by a later one recalls nothing")
    rig.clock.advance(by: 0.5)
    #expect(rig.notifier.notes.map(\.title) == ["Workspace desk"])
    rig.clock.advance(by: WorkspaceKeeper.settleSeconds * 2)
    #expect(rig.notifier.notes.count == 1, "a burst recalls once")
}

// Test 5: Plugging in the tied display set after another one recalls its workspace.
@Test func testKeeperRecallsTiedSet() {
    let rig = KeeperRig()
    let home = rig.screens.screens
    let before = rig.pads.map(rig.frame)
    rig.keeper.saveWorkspace("desk")
    rig.keeper.tie("desk")
    rig.screens.screens = Screens(
        full: [Frame(x: 0, y: 0, w: 1920, h: 1080)], usable: [Frame(x: 0, y: 25, w: 1920, h: 1055)],
        host: nil, isUltrawide: false)
    rig.keeper.screensChanged()
    rig.clock.advance(by: WorkspaceKeeper.settleSeconds)
    rig.windows.nudge(rig.pads[0], to: Frame(x: 100, y: 100, w: 400, h: 300))
    rig.screens.screens = home
    rig.keeper.screensChanged()
    rig.clock.advance(by: WorkspaceKeeper.settleSeconds)
    #expect(rig.notifier.notes.map(\.title) == ["Workspace desk"])
    #expect(rig.frame(rig.pads[0]) == before[0])
}

// Test 6: An app's rule places the first window of the app when it appears, never an app already
// showing windows at the first look.
@Test func testKeeperRuleFirstWindow() {
    let target = Frame(x: 1200, y: 300, w: 900, h: 700)
    let rig = KeeperRig {
        $0.appRules = [
            AppRule(bundle: "com.example.notes", frame: target), AppRule(bundle: "com.example.pad", frame: target),
        ]
    }
    rig.look()
    #expect(rig.frame(rig.pads[0]) != target && rig.frame(rig.pads[1]) != target)
    let notes = rig.windows.add(bundle: "com.example.notes", frame: Frame(x: 50, y: 50, w: 500, h: 400))
    rig.look()
    #expect(rig.frame(notes) == target)
}

// Test 7: Switching profile takes its settings and recalls its workspaces, and says what it did.
@Test func testKeeperApplyProfile() {
    let rig = KeeperRig()
    let before = rig.pads.map(rig.frame)
    rig.keeper.saveWorkspace("desk")
    rig.keeper.saveProfile("work")
    #expect(rig.anchors.choices.activeProfile == "work")
    rig.anchors.choices.profiles[0].workspaces = ["desk", "gone"]
    rig.windows.nudge(rig.pads[1], to: Frame(x: 2500, y: 600, w: 500, h: 300))
    #expect(rig.keeper.applyProfile("work"))
    #expect(rig.pads.map(rig.frame) == before)
    #expect(rig.notifier.notes.last?.title == "Profile work")
    #expect(!rig.keeper.applyProfile("nope"))
}

// Test 8: The display set key comes from the screen source, so a platform's own key decides ties.
@Test func testKeeperUsesSourceKey() {
    let rig = KeeperRig()
    rig.keeper.saveWorkspace("desk")
    rig.keeper.tie("desk")
    #expect(rig.anchors.choices.workspaces["desk"]?.setup == Workspaces.signature(rig.screens.screens.full))
}

// SplitRig drives a keeper through the displays a monitor split between two computers shows one of
// them: the whole panel, the share of it this computer keeps (by default one 1920x1440 half of an
// evenly split panel, wide enough for both sides to hold), and the laptop alone while the panel goes
// dark between modes. A mail window waits for the anchor the edit adds.
final class SplitRig {
    // rig is the keeper on fakes, starting on the whole panel.
    let rig = KeeperRig()
    // mail is the window the full mode edit anchors on the right.
    let mail: WindowID
    // full is the whole panel.
    let full: Screens
    // share is the part of the panel this computer keeps in the split.
    let share: Screens
    // laptop is the laptop display alone.
    let laptop = FakeScreens.laptop().screens

    // evenShare is the 1920x1440 half of an evenly split panel, not an ultrawide.
    static let evenShare = Screens(
        full: [Frame(x: 0, y: 0, w: 1920, h: 1440)], usable: [Frame(x: 0, y: 25, w: 1920, h: 1415)],
        host: 0, isUltrawide: false)
    // widePanel is a whole 5120x1440 panel, host found as the platform finds it.
    static let widePanel = Screens(
        full: [Frame(x: 0, y: 0, w: 5120, h: 1440)], usable: [Frame(x: 0, y: 25, w: 5120, h: 1415)])
    // wideShare is the 3360x1440 share the 21:9 split of widePanel gives, host found the same way.
    static let wideShare = Screens(
        full: [Frame(x: 0, y: 0, w: 3360, h: 1440)], usable: [Frame(x: 0, y: 25, w: 3360, h: 1415)])

    // init starts the rig on full and adds the mail window behind the pads.
    init(full: Screens = FakeScreens.ultrawide().screens, share: Screens = SplitRig.evenShare) {
        self.full = full
        self.share = share
        rig.screens.screens = full
        mail = rig.windows.add(
            bundle: "com.example.mail", frame: Frame(x: 600, y: 200, w: 600, h: 400), title: "inbox")
    }

    // show plugs in screens the way the platform reports it, then waits out the settle and the passes
    // it wakes, so a tied workspace comes back and the anchors hold on the new displays.
    func show(_ screens: Screens) {
        rig.screens.screens = screens
        rig.engine.handle(.screensChanged)
        rig.clock.advance(by: WorkspaceKeeper.settleSeconds)
        rig.clock.advance(by: Pace.settleSeconds + 1)
    }

    // setUp saves and ties a workspace to each of the three display sets: chosen widths and an anchor
    // on the whole panel, the windows as they rest on the share, and the laptop's own anchor.
    func setUp() {
        rig.anchors.choices.widths = Widths(left: 30, right: 25)
        rig.anchors.choices.slots[.leftTop] = "com.example.pad"
        rig.keeper.saveWorkspace("full")
        rig.keeper.tie("full")
        show(share)
        rig.keeper.saveWorkspace("share")
        rig.keeper.tie("share")
        show(laptop)
        rig.anchors.choices.slots = [.rightTop: "com.example.pad"]
        rig.keeper.saveWorkspace("laptop")
        rig.keeper.tie("laptop")
        rig.anchors.choices.slots = [.leftTop: "com.example.pad"]
        show(full)
    }

    // edit changes the widths and adds an anchor the way the owner would in full mode.
    func edit() {
        rig.anchors.choices.widths = Widths(left: 35, right: 30)
        rig.anchors.choices.slots[.rightTop] = "com.example.mail"
    }

    // expectEdits checks the full mode edit and its new anchor are still the choices.
    func expectEdits(_ comment: Comment) {
        #expect(rig.anchors.choices.widths == Widths(left: 35, right: 30), comment)
        #expect(rig.anchors.choices.slots[.rightTop] == "com.example.mail", comment)
        #expect(rig.anchors.choices.slots[.leftTop] == "com.example.pad", comment)
    }
}

// Test 9: A workspace a display change brings back moves its windows and leaves the widths and
// anchors chosen in the other mode alone, so toggling a split monitor twice keeps a full mode edit
// while the share holds the edited anchors in thirds.
@Test func testKeeperDisplayChangeKeepsEdits() {
    let s = SplitRig()
    s.setUp()
    s.edit()
    s.show(s.share)
    let third = 1920 * Layout.hostPair.right / 100
    let right = s.rig.frame(s.mail)
    let left = s.rig.pads.map(s.rig.frame)
    #expect(abs(right.w - third) < 1 && abs(right.x + right.w - 1920) < 1, "the share shows thirds: mail \(right)")
    #expect(left.contains { abs($0.w - third) < 1 && $0.x < 1 }, "the share shows thirds: pads \(left)")
    s.show(s.full)
    s.show(s.share)
    s.show(s.full)
    s.expectEdits("two toggles")
}

// Test 10: A blackout longer than the settle, with only the laptop showing between modes, brings
// back the laptop's workspace and still leaves the full mode edit alone.
@Test func testKeeperDisplayGapKeepsEdits() {
    let s = SplitRig()
    s.setUp()
    s.edit()
    s.show(s.laptop)
    s.show(s.share)
    s.show(s.laptop)
    s.show(s.full)
    s.expectEdits("laptop only between modes")
}

// Test 11: Recall by hand still restores the widths and anchors the workspace saved.
@Test func testKeeperManualRecallRestoresChoices() {
    let s = SplitRig()
    s.setUp()
    s.edit()
    #expect(s.rig.keeper.recall("full"))
    #expect(s.rig.anchors.choices.widths == Widths(left: 30, right: 25))
    #expect(s.rig.anchors.choices.slots == [.leftTop: "com.example.pad"])
}

// Test 12: The 21:9 share of a 5120 panel is an ultrawide of its own: after a switch to it the
// anchors hold its strips at the chosen widths, and two toggles, one with the panel dark and only
// the laptop showing, still leave the full mode edit alone.
@Test func testKeeperWideShareKeepsEdits() {
    let s = SplitRig(full: SplitRig.widePanel, share: SplitRig.wideShare)
    #expect(s.share.isUltrawide && s.share.host == 0, "the 21:9 share is an ultrawide host")
    s.setUp()
    s.edit()
    s.show(s.share)
    #expect(s.rig.anchors.hostIsUltrawide, "the anchors see the share as an ultrawide")
    let right = s.rig.frame(s.mail)
    let left = s.rig.pads.map(s.rig.frame)
    #expect(abs(right.w - 3360 * 0.30) < 1 && abs(right.x + right.w - 3360) < 1, "mail holds the right strip: \(right)")
    #expect(left.contains { abs($0.w - 3360 * 0.35) < 1 && $0.x < 1 }, "a pad holds the left strip: \(left)")
    s.show(s.full)
    s.show(s.laptop)
    s.show(s.share)
    s.show(s.full)
    s.expectEdits("toggles through the 21:9 share")
    let back = s.rig.frame(s.mail)
    #expect(abs(back.w - 5120 * 0.30) < 1 && abs(back.x + back.w - 5120) < 1, "mail holds the panel's strip: \(back)")
}

// Test 13: The 50:50 split of a 5120 panel gives a 2560x1440 share, which is not an ultrawide, so
// the anchors use the normal display's fixed widths there and the full mode edit survives.
@Test func testKeeperEvenShareOfWidePanel() {
    let even = Screens(
        full: [Frame(x: 0, y: 0, w: 2560, h: 1440)], usable: [Frame(x: 0, y: 25, w: 2560, h: 1415)])
    let s = SplitRig(full: SplitRig.widePanel, share: even)
    #expect(!s.share.isUltrawide, "the 16:9 share is a normal display")
    s.setUp()
    s.edit()
    s.show(s.share)
    #expect(!s.rig.anchors.hostIsUltrawide, "the anchors see the share as a normal display")
    s.show(s.full)
    s.expectEdits("a toggle through the 16:9 share")
}
