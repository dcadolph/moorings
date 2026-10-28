// Timers hands out schedulers, one per engine object that defers work.
public protocol Timers: AnyObject {
    // scheduler returns a new, independent scheduler for one engine object's deferred work.
    func scheduler() -> any Scheduler
}
