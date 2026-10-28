// Scheduler runs one piece of deferred work on the engine's thread.
public protocol Scheduler: AnyObject {
    // schedule runs work at time at on the engine's thread, replacing any pending work.
    func schedule(at: Double, _ work: @escaping () -> Void)
    // cancel drops the pending work.
    func cancel()
}
