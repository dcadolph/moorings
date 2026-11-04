import Foundation
import Testing

import MooringsCore

@testable import Moorings

// A slot change made while paused says nothing moves until Resume Moorings, and says nothing
// otherwise.
@Test @MainActor func testPausedNotice() {
    let tests: [(paused: Bool, change: String, want: String?)] = [
        // Test 0: Not paused.
        (false, "Google Chrome is anchored to the left top slot", nil),
        // Test 1: Paused, an app anchored.
        (
            true, "Google Chrome is anchored to the left top slot",
            "Google Chrome is anchored to the left top slot, but nothing moves while paused. "
                + "Choose Resume Moorings in the menu to apply it."
        ),
        // Test 2: Paused, an app unanchored.
        (
            true, "Finder is unanchored",
            "Finder is unanchored, but nothing moves while paused. Choose Resume Moorings in the menu to apply it."
        ),
    ]
    for (i, test) in tests.enumerated() {
        let got = MenuBuilder.pausedNotice(paused: test.paused, change: test.change)
        #expect(got == test.want, "test \(i)")
    }
}

// Anchoring with no ultrawide attached explains why nothing moves, and says nothing with one.
@Test @MainActor func testNoUltrawide() {
    let tests: [(wide: Frame?, wantTitle: String?, wantBody: String?)] = [
        // Test 0: No ultrawide.
        (
            nil, "Anchoring needs an ultrawide",
            "Teams stays where it is. Anchored apps live in the side strips of an ultrawide, a display "
                + "at least 2.2 times as wide as it is tall, and none is attached now. Choose Anchor "
                + "anyway to have Teams take the slot the next time one is attached."
        ),
        // Test 1: An ultrawide is attached.
        (Frame(x: 0, y: 25, w: 3440, h: 1415), nil, nil),
    ]
    for (i, test) in tests.enumerated() {
        let got = MenuBuilder.noUltrawide("Teams", wide: test.wide)
        #expect(got?.title == test.wantTitle, "test \(i)")
        #expect(got?.body == test.wantBody, "test \(i)")
    }
}

// The install box is disabled and unchecked while the automatic check is off, and both boxes show
// their choices otherwise.
@Test @MainActor func testUpdateChoices() {
    let tests: [(check: Bool, install: Bool, wantInstallOn: Bool, wantInstallEnabled: Bool)] = [
        // Test 0: Both on.
        (true, true, true, true),
        // Test 1: Check on, install off.
        (true, false, false, true),
        // Test 2: Check off disables install.
        (false, true, false, false),
        // Test 3: Both off.
        (false, false, false, false),
    ]
    for (i, test) in tests.enumerated() {
        let items = MenuBuilder.updateChoices(
            check: test.check, install: test.install, toggleCheck: {}, toggleInstall: {})
        let titles = ["Check for updates automatically", "Install updates automatically"]
        #expect(items.map(\.title) == titles, "test \(i)")
        #expect(items[0].state == (test.check ? .on : .off), "test \(i)")
        #expect(items[1].state == (test.wantInstallOn ? .on : .off), "test \(i)")
        let install = items[1] as? ActionItem
        #expect(install?.validateMenuItem(items[1]) == test.wantInstallEnabled, "test \(i)")
        #expect(items[1].isEnabled == test.wantInstallEnabled, "test \(i)")
    }
}

// The top line names the update's state. The staged update installs now when chosen, and a newer
// release updates now when this copy can replace itself, else opens its page.
@Test @MainActor func testUpdateLine() {
    let page = URL(string: "https://github.com/dcadolph/moorings/releases/tag/v9.0.0")!
    let release = ReleaseInfo(tag: "v9.0.0", page: page)
    let tests:
        [(
            state: UpdateState, release: ReleaseInfo?, replace: Bool, want: String?, wantEnabled: Bool,
            wantInstall: Int, wantUpdate: Int
        )] = [
            // Test 0: Nothing newer.
            (.idle, nil, true, nil, false, 0, 0),
            // Test 1: A newer release this copy can replace itself with.
            (.idle, release, true, "Update to v9.0.0 now", true, 0, 1),
            // Test 2: A newer release this copy cannot install, which opens the page.
            (.idle, release, false, "Update available: v9.0.0", true, 0, 0),
            // Test 3: Downloading.
            (.downloading("v9.0.0"), release, true, "Downloading v9.0.0", false, 0, 0),
            // Test 4: Staged, chosen to install now.
            (.verified("v9.0.0"), release, true, "v9.0.0 ready, installs when you're idle", true, 1, 0),
            // Test 5: Installing.
            (.installing("v9.0.0"), release, true, "Installing v9.0.0", false, 0, 0),
            // Test 6: Refused.
            (
                .refused(.notarization, "v9.0.0"), release, true, "v9.0.0 could not be verified (notarization)", true,
                0, 0
            ),
        ]
    for (i, test) in tests.enumerated() {
        var installs = 0
        var updates = 0
        var updateNow: (@MainActor () -> Void)?
        if test.replace {
            updateNow = { updates += 1 }
        }
        let line =
            MenuBuilder.updateLine(
                test.state, release: test.release, installNow: { installs += 1 }, updateNow: updateNow)
            as? ActionItem
        #expect(line?.title == test.want, "test \(i)")
        if let line {
            #expect(line.validateMenuItem(line) == test.wantEnabled, "test \(i)")
            if test.wantInstall + test.wantUpdate > 0 {
                _ = line.perform(line.action!)
            }
        }
        #expect(installs == test.wantInstall && updates == test.wantUpdate, "test \(i)")
    }
}
