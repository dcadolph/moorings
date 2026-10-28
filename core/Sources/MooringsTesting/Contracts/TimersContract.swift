import MooringsEngine

// TimersContract checks that each scheduler from a Timers is independent of the others and keeps the
// Scheduler rules.
public enum TimersContract {
    // run checks subject and clock while host runs the platform and returns every rule they broke.
    public static func run(_ subject: Timers, clock: Clock, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let a = subject.scheduler()
        let b = subject.scheduler()
        if a === b {
            out.append(ContractFailure(rule: "each scheduler is a new one", detail: "the same scheduler twice"))
        }
        var ran: [String] = []
        a.schedule(at: clock.now + 0.05) { ran.append("a") }
        b.schedule(at: clock.now + 0.05) { ran.append("b") }
        b.cancel()
        _ = host.wait(until: host.now + 1) { !ran.isEmpty }
        _ = host.wait(until: host.now + 0.2) { false }
        if ran != ["a"] {
            out.append(
                ContractFailure(
                    rule: "work on one scheduler runs when another is canceled, and only its own", detail: "ran \(ran)")
            )
        }
        out += SchedulerContract.run(subject.scheduler(), clock: clock, host: host)
        return out
    }
}
