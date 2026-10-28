import MooringsCore
import MooringsEngine

// MacKeys is the Mac Keys: the Carbon hotkeys, which bind the shortcuts and also take the keys a hold
// grabs.
@MainActor
final class MacKeys: @preconcurrency Keys {
    // hotkeys registers the shortcuts and the grabbed keys.
    private let hotkeys: Hotkeys

    // init builds the keys over hotkeys.
    init(_ hotkeys: Hotkeys) {
        self.hotkeys = hotkeys
    }

    // shortcutsOn reports whether the shortcuts are registered.
    var shortcutsOn: Bool { hotkeys.enabled }

    // bind registers the shortcuts in map; the delegate logs the problems Bindings finds before.
    func bind(_ map: [String: Shortcut]) {
        hotkeys.bind(map)
    }

    // grab registers keys until ungrab and delivers each press to handler by tag.
    @discardableResult
    func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        hotkeys.grab(keys, handler)
    }

    // ungrab lets the grabbed keys go.
    func ungrab() {
        hotkeys.ungrab()
    }

    // spell writes a shortcut with the Mac's modifier symbols.
    func spell(_ s: Shortcut) -> String {
        s.spelled
    }
}
