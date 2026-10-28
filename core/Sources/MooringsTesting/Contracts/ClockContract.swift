import MooringsEngine

// ClockContract checks that a Clock never runs backward and keeps close to the host's own clock.
public enum ClockContract {
    // run checks subject while host waits and returns every rule it broke.
    public static func run(_ subject: Clock, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let first = subject.now
        _ = host.wait(until: host.now + 0.05) { false }
        let second = subject.now
        _ = host.wait(until: host.now + 0.05) { false }
        let third = subject.now
        if second < first || third < second {
            fail("the clock is monotonic", "read \(first), \(second), \(third)")
        }
        let skew = abs(subject.now - host.now)
        if skew > 0.05 {
            fail("the clock stays within 50 ms of the host's clock", "apart \(skew) s")
        }
        return out
    }
}
