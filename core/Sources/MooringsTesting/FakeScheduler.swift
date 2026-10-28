import MooringsEngine

// FakeScheduler is a Scheduler that keeps one pending piece of work for its FakeClock to run.
public final class FakeScheduler: Scheduler {
    // pendingAt is when the pending work runs, nil when nothing is pending.
    public private(set) var pendingAt: Double?
    // runs counts the pieces of work that ran.
    public private(set) var runs = 0
    // work is the pending work.
    private var work: (() -> Void)?

    // init builds a scheduler whose work runs as clock advances.
    public init(clock: FakeClock) {
        clock.attach(self)
    }

    // schedule replaces any pending work with work at time at.
    public func schedule(at: Double, _ work: @escaping () -> Void) {
        pendingAt = at
        self.work = work
    }

    // cancel drops the pending work.
    public func cancel() {
        pendingAt = nil
        work = nil
    }

    // fire runs the pending work once and clears it first, so the work may schedule more.
    func fire() {
        guard let w = work else { return }
        cancel()
        runs += 1
        w()
    }
}
