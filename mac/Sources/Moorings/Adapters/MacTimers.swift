import MooringsEngine

// MacTimers is the Mac Timers: each scheduler is its own main run loop timer.
@MainActor
final class MacTimers: @preconcurrency Timers {
    // scheduler returns a new MacScheduler.
    func scheduler() -> any Scheduler {
        MacScheduler()
    }
}
