import MooringsEngine

// FakeClock is a Clock that moves only when a test advances it, running due scheduled work on the way.
public final class FakeClock: Clock {
    // now is the current time in seconds.
    public private(set) var now: Double
    // schedulers lists the schedulers whose work advance runs.
    private var schedulers: [FakeScheduler] = []

    // init builds a clock at start.
    public init(_ start: Double = 0) {
        now = start
    }

    // attach makes advance run the scheduler's work when it falls due.
    func attach(_ scheduler: FakeScheduler) {
        schedulers.append(scheduler)
    }

    // advance moves the clock to time t, running each due piece of work at its own time, earliest
    // first, so work that schedules more work inside the span runs too.
    public func advance(to t: Double) {
        precondition(t >= now, "FakeClock.advance: time runs forward only")
        for _ in 0..<10_000 {
            let due = schedulers.compactMap { s in s.pendingAt.map { (s, $0) } }.filter { $0.1 <= t }
            guard let next = due.min(by: { $0.1 < $1.1 }) else { break }
            now = max(now, next.1)
            next.0.fire()
        }
        now = t
    }

    // advance moves the clock forward by seconds.
    public func advance(by seconds: Double) {
        advance(to: now + seconds)
    }
}
