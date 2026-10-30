import Testing

import MooringsCore
import MooringsEngine

@testable import Moorings

// The source lists the running apps when it starts and not again on each pass within
// PassPlan.appsSeconds, since reading every app's kind costs a system call per app.
@MainActor
@Test func testWatchListsAppsOnlyWhenDue() {
    let events = MacEvents(store: Windows(), listApps: { [] })
    events.start { _ in }
    defer { events.stop() }
    #expect(events.listCount == 1)
    for _ in 0..<10 {
        events.watch(Scan(windows: [], focused: nil))
    }
    #expect(events.listCount == 1)
}
