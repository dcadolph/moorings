import MooringsCore
import MooringsEngine

// AppsContract checks that Apps names the host's app, refuses an app that does not exist, and opens
// the host's app with a window the store lists within 5 s.
public enum AppsContract {
    // missing is a bundle id no platform has.
    static let missing = "com.example.moorings.no-such-app"

    // run checks subject over the host's app read through store and returns every rule it broke. It
    // closes the windows the open made.
    public static func run(_ subject: Apps, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        guard let app = host.knownApp else {
            Contract.skip("apps rules", "the host has no app to open")
            return out
        }
        let name = subject.name(app)
        if name.isEmpty || name == app {
            fail("name of the host's app is a name, not the id", "got \"\(name)\"")
        }
        if subject.open(missing, background: true, target: nil) {
            fail("open of an app that does not exist returns false", "returned true")
        }
        let screens = host.screens()
        let before = Set(store.scan(screens, full: true).windows.map(\.id))
        var made: [WindowID] = []
        if !subject.open(app, background: false, target: nil) {
            fail("open of the host's app returns true", "returned false")
        } else if !host.wait(
            until: host.now + 5,
            {
                made = store.scan(screens, full: true).windows.filter { $0.bundle == app && !before.contains($0.id) }
                    .map(\.id)
                return !made.isEmpty
            })
        {
            fail("open of the host's app shows a window in scan within 5 s", "no new window")
        }
        for id in made {
            store.close(id)
        }
        return out
    }
}
