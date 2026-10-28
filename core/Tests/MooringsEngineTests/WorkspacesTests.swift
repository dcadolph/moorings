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
    // anchors holds the choices.
    let anchors: Anchors
    // keeper is the keeper under test.
    let keeper: WorkspaceKeeper
    // pads lists the free windows, back to front.
    var pads: [WindowID] = []
    // titles maps a window to its title.
    var titles: [WindowID: String] = [:]
    // opened lists the apps the keeper opened, with their targets.
    var opened: [String] = []
    // later holds the work the keeper deferred, with its delay.
    var later: [(Double, () -> Void)] = []
    // saves counts the times the keeper reported a change.
    var saves = 0

    // init builds the rig with choices changed by edit.
    init(_ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices()
        edit(&c)
        anchors = Anchors(choices: c)
        let platform = Platform(windows: windows, screens: screens, overlay: FakeOverlay(), notifier: notifier,
                                clock: clock, scheduler: FakeScheduler(clock: clock), store: FakeStore(),
                                warpCursor: { _ in })
        let organizer = Organizer(platform: platform, anchors: anchors)
        keeper = WorkspaceKeeper(platform: platform, anchors: anchors, organizer: organizer,
                                 actions: ActionRunner(platform: platform, anchors: anchors))
        pads.append(windows.add(bundle: "com.example.pad", frame: Frame(x: 900, y: 200, w: 700, h: 500)))
        pads.append(windows.add(bundle: "com.example.pad", frame: Frame(x: 1700, y: 300, w: 600, h: 400), focus: true))
        titles = [pads[0]: "one", pads[1]: "two"]
        let rig = self
        keeper.title = { rig.titles[$0] ?? "" }
        keeper.openApp = { bundle, target in rig.opened.append(bundle + (target.map { " " + $0 } ?? "")) }
        keeper.after = { seconds, work in rig.later.append((seconds, work)) }
        keeper.changed = { rig.saves += 1 }
    }

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

// Test 3: A saved window whose app is not running opens the app, and its first window goes where
// the workspace saved it, then is checked once more a moment later.
@Test func testKeeperOpensMissingApp() {
    let rig = KeeperRig()
    let saved = Frame(x: 1000, y: 400, w: 800, h: 600)
    rig.anchors.choices.workspaces["mail"] = Workspace(
        name: "mail", slots: [:], widths: nil, heights: nil,
        windows: [SavedWindow(bundle: "com.example.mail", title: "Inbox", frame: saved, launchBundle: "com.example.mail")],
        setup: nil)
    rig.look()
    #expect(rig.keeper.recall("mail"))
    #expect(rig.opened == ["com.example.mail"])
    #expect(rig.keeper.waiting)
    #expect(rig.notifier.notes.last?.body == "Recalled. Opening 1 app.")
    let mail = rig.windows.add(bundle: "com.example.mail", frame: Frame(x: 50, y: 50, w: 500, h: 400))
    rig.look()
    #expect(rig.frame(mail) == saved)
    #expect(!rig.keeper.waiting)
    #expect(rig.keeper.deadlines() == [rig.clock.now + WorkspaceKeeper.recheckSeconds])
}

// Test 4: A tie follows the display set key, and a burst of display changes recalls the tied
// workspace once, from the last change of the burst after the displays settle.
@Test func testKeeperTieAndDisplayChange() {
    let rig = KeeperRig()
    let office = Screens(full: [Frame(x: 0, y: 0, w: 1920, h: 1080)], usable: [Frame(x: 0, y: 25, w: 1920, h: 1055)],
                         ultrawide: nil)
    rig.screens.screens = office
    rig.keeper.saveWorkspace("desk")
    rig.keeper.tie("desk")
    #expect(rig.keeper.tied("desk"))
    rig.screens.screens = FakeScreens.ultrawide().screens
    #expect(!rig.keeper.tied("desk"))
    rig.screens.screens = office
    rig.keeper.screensChanged()
    rig.keeper.screensChanged()
    #expect(rig.later.count == 2 && rig.later.allSatisfy { $0.0 == WorkspaceKeeper.settleSeconds })
    rig.later[0].1()
    #expect(rig.notifier.notes.isEmpty, "a change superseded by a later one recalls nothing")
    rig.later[1].1()
    #expect(rig.notifier.notes.map(\.title) == ["Workspace desk"])
}

// Test 5: Plugging in the tied display set after another one recalls its workspace.
@Test func testKeeperRecallsTiedSet() {
    let rig = KeeperRig()
    let home = rig.screens.screens
    let before = rig.pads.map(rig.frame)
    rig.keeper.saveWorkspace("desk")
    rig.keeper.tie("desk")
    rig.screens.screens = Screens(full: [Frame(x: 0, y: 0, w: 1920, h: 1080)], usable: [Frame(x: 0, y: 25, w: 1920, h: 1055)],
                                  ultrawide: nil)
    rig.keeper.screensChanged()
    rig.later.removeLast().1()
    rig.windows.nudge(rig.pads[0], to: Frame(x: 100, y: 100, w: 400, h: 300))
    rig.screens.screens = home
    rig.keeper.screensChanged()
    rig.later.removeLast().1()
    #expect(rig.notifier.notes.map(\.title) == ["Workspace desk"])
    #expect(rig.frame(rig.pads[0]) == before[0])
}

// Test 6: An app's rule places the first window of the app when it appears, never an app already
// showing windows at the first look.
@Test func testKeeperRuleFirstWindow() {
    let target = Frame(x: 1200, y: 300, w: 900, h: 700)
    let rig = KeeperRig {
        $0.appRules = [AppRule(bundle: "com.example.notes", frame: target), AppRule(bundle: "com.example.pad", frame: target)]
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
