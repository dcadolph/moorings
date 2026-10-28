import Foundation

import MooringsCore
import MooringsEngine

// MacActions is the Mac PlatformActions: the menu under the pointer and the strip editor, each
// opened one main queue turn later so the shortcut or button that asked is done first.
@MainActor
final class MacActions: @preconcurrency PlatformActions {
    // app is the running app delegate, which owns the menu and the strip editor.
    private unowned let app: AppDelegate

    // init builds the actions on app.
    init(app: AppDelegate) {
        self.app = app
    }

    // handles reports whether name is the menu or the strip editor.
    func handles(_ name: String) -> Bool {
        name == Keymaps.menuName || name == Keymaps.stripsName
    }

    // run opens the menu or the strip editor and reports whether name is one of them.
    func run(_ name: String, window: WindowID?) -> Bool {
        switch name {
        case Keymaps.menuName:
            DispatchQueue.main.async { [app] in app.popMenu() }
            return true
        case Keymaps.stripsName:
            DispatchQueue.main.async { [app] in app.strips.show() }
            return true
        default:
            return false
        }
    }
}
