import MooringsEngine

// NotifierContract checks that a Notifier returns at once and leaves the focus where it was.
public enum NotifierContract {
    // limit is how long notify may take to return, in seconds.
    public static let limit = 0.5

    // run checks subject over a focused host window read through store and returns every rule it broke.
    public static func run(_ subject: Notifier, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer { host.finish() }
        guard let a = Contract.focus(store, host, &out) else { return out }
        let start = host.now
        subject.notify("Moorings contract", "A banner that takes no focus.")
        let took = host.now - start
        if took > limit {
            out.append(ContractFailure(rule: "notify returns within 500 ms", detail: "took \(took) s"))
        }
        _ = host.wait(until: host.now + 0.25) { false }
        if store.scan(host.screens(), full: true).focused?.id != a {
            out.append(ContractFailure(rule: "notify does not take focus", detail: "focus moved off \(a)"))
        }
        return out
    }
}
