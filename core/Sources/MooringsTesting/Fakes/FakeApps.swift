import MooringsCore
import MooringsEngine

// FakeApps is an Apps over FakeWindows: opening a known app adds one of its windows.
public final class FakeApps: Apps {
    // names maps each known bundle id to its name.
    public var names: [String: String]
    // opened records every app that opened, in order.
    public private(set) var opened: [String] = []
    // windows is the store an opened app's window appears in.
    private let windows: FakeWindows

    // init builds apps that know names and open windows in windows.
    public init(windows: FakeWindows, names: [String: String] = ["contract.host": "Contract Host"]) {
        self.windows = windows
        self.names = names
    }

    // name returns the known name, or the id itself for an app it does not know.
    public func name(_ bundle: String) -> String {
        names[bundle] ?? bundle
    }

    // open adds a window of a known app and returns true; an unknown app opens nothing.
    public func open(_ bundle: String, background: Bool, target: String?) -> Bool {
        guard names[bundle] != nil else { return false }
        opened.append(bundle)
        windows.add(bundle: bundle, frame: Frame(x: 800, y: 300, w: 700, h: 500), focus: !background)
        return true
    }
}
