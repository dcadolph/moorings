import AppKit

import MooringsCore

// StripEditor shows the strips over the ultrawide with a handle on each inner edge and row line, so
// the widths and heights can be stepped, typed or dragged while the windows follow.
@MainActor
final class StripEditor {
    // app is the running app delegate.
    private unowned let app: AppDelegate

    // init builds a strip editor for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // show opens the editor over the ultrawide and reports whether it opened.
    @discardableResult
    func show() -> Bool {
        false
    }
}
