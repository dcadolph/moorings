import MooringsCore
import MooringsEngine

// MacKeys is the Mac Keys: the Carbon hotkeys, which bind the shortcuts and also take the keys a hold
// grabs, and the key tap, which takes the keys a claim holds ahead of macOS's own shortcuts.
@MainActor
final class MacKeys: @preconcurrency Keys {
    // hotkeys registers the shortcuts and the grabbed keys.
    private let hotkeys: Hotkeys
    // tap takes the claimed keys while the shortcuts are on.
    private let tap: KeyTap

    // init builds the keys over hotkeys, with a key tap that passes every key while the shortcuts
    // are off.
    init(_ hotkeys: Hotkeys) {
        self.hotkeys = hotkeys
        tap = KeyTap { [unowned hotkeys] in hotkeys.enabled }
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

    // claim takes keys through the key tap until unclaim, whatever is grabbed or bound, and delivers
    // each press to handler by tag.
    @discardableResult
    func claim(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        tap.claim(keys, handler)
    }

    // unclaim lets the claimed keys go and removes the key tap.
    func unclaim() {
        tap.unclaim()
    }

    // spell writes a shortcut with the Mac's modifier symbols.
    func spell(_ s: Shortcut) -> String {
        s.spelled
    }
}
