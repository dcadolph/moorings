// Clock tells the time the engine schedules against.
public protocol Clock: AnyObject {
    // now is seconds on a monotonic clock shared with the adapter's own timestamps.
    var now: Double { get }
}
