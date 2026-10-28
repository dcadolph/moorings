import MooringsEngine

// SchedulerContract checks that a Scheduler runs work once when due, cancels it, and replaces it, and
// that its Clock runs forward with the host's own.
public enum SchedulerContract {
    // run checks subject and clock while host runs the platform and returns every rule they broke.
    public static func run(_ subject: Scheduler, clock: Clock, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let skew = abs(clock.now - host.now)
        if skew > 0.05 {
            fail("the clock stays within 50 ms of the host's clock", "apart \(skew) s")
        }
        var runs: [Double] = []
        let at = clock.now + 0.1
        subject.schedule(at: at) { runs.append(clock.now) }
        _ = host.wait(until: host.now + 1) { !runs.isEmpty }
        _ = host.wait(until: host.now + 0.3) { false }
        if runs.count != 1 {
            fail("work runs once", "ran \(runs.count) times")
        } else if runs[0] < at - 0.001 {
            fail("work runs at or after its time", "asked \(at) ran \(runs[0])")
        }
        var cancelled = false
        subject.schedule(at: clock.now + 0.05) { cancelled = true }
        subject.cancel()
        _ = host.wait(until: host.now + 0.3) { false }
        if cancelled {
            fail("cancel stops the pending work", "it ran")
        }
        var which: [String] = []
        subject.schedule(at: clock.now + 0.05) { which.append("first") }
        subject.schedule(at: clock.now + 0.1) { which.append("second") }
        _ = host.wait(until: host.now + 1) { !which.isEmpty }
        _ = host.wait(until: host.now + 0.2) { false }
        if which != ["second"] {
            fail("a second schedule replaces the first", "ran \(which)")
        }
        let before = clock.now
        _ = host.wait(until: host.now + 0.05) { false }
        if clock.now < before {
            fail("the clock is monotonic", "went from \(before) to \(clock.now)")
        }
        return out
    }
}
