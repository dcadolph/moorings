import MooringsCore
import MooringsEngine

// WinKeys is the Windows Keys: the RegisterHotKey shortcuts, which also take the keys a hold grabs.
final class WinKeys: Keys {
    // hotkeys registers the shortcuts and the grabbed keys.
    private let hotkeys: WinHotkeys

    // init builds the keys over hotkeys.
    init(_ hotkeys: WinHotkeys) {
        self.hotkeys = hotkeys
    }

    // shortcutsOn is true: Windows has no switch that turns the shortcuts off.
    var shortcutsOn: Bool { true }

    // grab registers keys until ungrab and delivers each press to handler by tag.
    @discardableResult
    func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        hotkeys.grab(keys, handler)
    }

    // ungrab lets the grabbed keys go.
    func ungrab() {
        hotkeys.ungrab()
    }

    // spell writes a shortcut the way Windows does, such as Ctrl+Alt+Left.
    func spell(_ s: Shortcut) -> String {
        WinHotkeys.spelled(s)
    }
}
