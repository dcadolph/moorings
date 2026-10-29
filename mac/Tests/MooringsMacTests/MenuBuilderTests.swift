import Testing

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
