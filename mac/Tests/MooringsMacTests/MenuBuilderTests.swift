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

// The top line names the update's state, and only a refusal or an offered release can be chosen.
@Test @MainActor func testUpdateLine() {
    let page = URL(string: "https://github.com/dcadolph/moorings/releases/tag/v9.0.0")!
    let release = ReleaseInfo(tag: "v9.0.0", page: page)
    let tests: [(state: UpdateState, release: ReleaseInfo?, want: String?, wantEnabled: Bool)] = [
        // Test 0: Nothing newer.
        (.idle, nil, nil, false),
        // Test 1: A newer release offered.
        (.idle, release, "Update available: v9.0.0", true),
        // Test 2: Downloading.
        (.downloading("v9.0.0"), release, "Downloading v9.0.0", false),
        // Test 3: Staged.
        (.verified("v9.0.0"), release, "v9.0.0 ready, installs when you pause", false),
        // Test 4: Installing.
        (.installing("v9.0.0"), release, "Installing v9.0.0", false),
        // Test 5: Refused.
        (.refused(.notarization, "v9.0.0"), release, "v9.0.0 could not be verified (notarization)", true),
    ]
    for (i, test) in tests.enumerated() {
        let line = MenuBuilder.updateLine(test.state, release: test.release) as? ActionItem
        #expect(line?.title == test.want, "test \(i)")
        if let line {
            #expect(line.validateMenuItem(line) == test.wantEnabled, "test \(i)")
        }
    }
}
