import ApplicationServices
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

// A quiet source turns a window's move into a bare wake and asks nothing, and a source that is not
// quiet asks the window's id.
@MainActor
@Test func testQuietEventReadsNothing() {
    let events = MacEvents(store: Windows(), listApps: { [] })
    var got: [WindowEvent] = []
    events.quiet(true)
    events.start { got.append($0) }
    defer { events.stop() }
    let el = AXUIElementCreateApplication(getpid())
    var before = Windows.roundTrips
    events.axEvent(el, kAXWindowMovedNotification)
    #expect(Windows.roundTrips - before == 0)
    #expect(got == [.wake])
    events.quiet(false)
    before = Windows.roundTrips
    events.axEvent(el, kAXWindowMovedNotification)
    #expect(Windows.roundTrips - before >= 1)
}
