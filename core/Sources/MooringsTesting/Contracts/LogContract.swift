import MooringsEngine

// LogContract checks that a Log takes a line in every category and returns at once. It times the note
// with the system's continuous clock, since a platform clock may tick more coarsely than the limit.
public enum LogContract {
    // limit is how long note may take to return.
    public static let limit = Duration.milliseconds(10)

    // run checks subject and returns every rule it broke.
    public static func run(_ subject: Log) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let clock = ContinuousClock()
        for category in LogCategory.allCases {
            let took = clock.measure { subject.note(category, "Moorings contract line.") }
            if took > limit {
                out.append(
                    ContractFailure(rule: "note returns within 10 ms", detail: "\(category.rawValue) took \(took)"))
            }
        }
        return out
    }
}
