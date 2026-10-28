import MooringsEngine

// FakeTimers is a Timers whose schedulers all run as one FakeClock advances.
public final class FakeTimers: Timers {
    // made lists every scheduler handed out, in order.
    public private(set) var made: [FakeScheduler] = []
    // clock is the clock the schedulers run on.
    private let clock: FakeClock

    // init builds timers on clock.
    public init(clock: FakeClock) {
        self.clock = clock
    }

    // scheduler returns a new FakeScheduler on the clock.
    public func scheduler() -> any Scheduler {
        let s = FakeScheduler(clock: clock)
        made.append(s)
        return s
    }
}
