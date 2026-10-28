import AppKit
import os

import MooringsCore

// NamePrompt asks for the name of a workspace or a profile.
@MainActor
enum NamePrompt {
    // ask asks for a name, nil when canceled or empty. The default wording names a workspace.
    static func ask(
        _ title: String = "Save workspace",
        _ info: String = "Name this layout: the slots, widths, heights and where each free window sits."
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
