import MooringsEngine

// LogContract checks that a Log takes a line in every category and returns at once.
public enum LogContract {
    // limit is how long note may take to return, in seconds.
    public static let limit = 0.01

    // run checks subject while host runs the platform and returns every rule it broke.
    public static func run(_ subject: Log, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        for category in LogCategory.allCases {
            let start = host.now
            subject.note(category, "Moorings contract line.")
            let took = host.now - start
            if took > limit {
                out.append(
                    ContractFailure(rule: "note returns within 10 ms", detail: "\(category.rawValue) took \(took) s"))
            }
        }
        return out
    }
}
