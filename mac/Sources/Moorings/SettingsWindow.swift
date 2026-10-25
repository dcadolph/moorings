import AppKit
import SwiftUI
import UniformTypeIdentifiers

import MooringsCore

// SettingsModel holds the choices the settings window shows and saves each change through the app.
@MainActor
final class SettingsModel: ObservableObject {
    // app is the running app delegate.
    unowned let app: AppDelegate
    // choices mirrors the app's choices.
    @Published private(set) var choices: Choices
    // message is the last export or import result, empty when none.
    @Published var message = ""

    // init builds a model for app.
    init(app: AppDelegate) {
        self.app = app
        choices = app.anchors.choices
    }

    // change applies edit to the choices, saves them, and shows the result.
    func change(_ edit: (inout Choices) -> Void) {
        edit(&app.anchors.choices)
        app.save()
        choices = app.anchors.choices
    }

    // reload picks up changes made from the menu.
    func reload() {
        choices = app.anchors.choices
    }

    // bindings returns the shortcuts and sizes in effect.
    var bindings: Bindings { Bindings(choices) }

    // suspend turns the window shortcuts off while a recorder listens, and back on after.
    func suspend(_ on: Bool) {
        if on {
            app.hotkeys.setEnabled(false)
        } else {
            app.refreshShortcuts()
        }
    }

    // exportSettings writes the choices to a file the owner picks.
    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SettingsBackup.fileName
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.encode(choices, exported: Date()).write(to: url, options: .atomic)
            message = "Exported to \(url.lastPathComponent)."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    // importSettings replaces the choices with a file the owner picks.
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try SettingsBackup.decode(try Data(contentsOf: url))
            change { $0 = imported }
            message = "Imported \(url.lastPathComponent)."
        } catch BackupError.notMoorings(let app) {
            message = "That file holds settings for \(app), not Moorings."
        } catch BackupError.newerVersion {
            message = "That file comes from a newer Moorings. Update first."
        } catch {
            message = "That file is not a Moorings settings file."
        }
    }

    // importRectangle carries Rectangle's settings over, from an export file or, without one, from the
    // settings Rectangle keeps on this Mac. It lists what cannot come over and asks before applying.
    func importRectangle() {
        let source = NSAlert()
        source.messageText = "Import from Rectangle"
        source.informativeText = "Choose a file exported from Rectangle's settings, or read the settings "
            + "Rectangle keeps on this Mac."
        source.addButton(withTitle: "Choose Export File…")
        source.addButton(withTitle: "Use Rectangle on This Mac")
        source.addButton(withTitle: "Cancel")
        let imported: Choices
        let warnings: [String]
        let from: String
        switch source.runModal() {
        case .alertFirstButtonReturn:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                (imported, warnings) = try RectangleImport.apply(try Data(contentsOf: url), to: choices)
            } catch RectangleImportError.wrongApp(let app) {
                message = "That file holds settings for \(app), not Rectangle."
                return
            } catch {
                message = "That file is not a Rectangle export."
                return
            }
            from = url.lastPathComponent
        case .alertSecondButtonReturn:
            let domain = UserDefaults.standard.persistentDomain(forName: RectangleImport.domain) ?? [:]
            guard RectangleImport.hasLiveSettings(domain) else {
                message = "Rectangle has no settings on this Mac, so there is nothing to import."
                return
            }
            (imported, warnings) = RectangleImport.applyLive(domain, to: choices)
            from = "Rectangle on this Mac"
        default:
            return
        }
        guard imported != choices || !warnings.isEmpty else {
            message = "\(from) holds nothing that differs from these settings."
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Apply Rectangle's settings?"
        var text = "Shortcuts and behavior choices from \(from) replace the ones here."
        if !warnings.isEmpty {
            let shown = warnings.prefix(12).joined(separator: "\n")
            let more = warnings.count > 12 ? "\nand \(warnings.count - 12) more." : ""
            text += "\n\nThese do not come over:\n\(shown)\(more)"
        }
        confirm.informativeText = text
        confirm.addButton(withTitle: "Import")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        change { $0 = imported }
        message = "Imported Rectangle's settings from \(from)."
    }
}

// SettingsWindow is the settings window, built once and shown again on each open.
@MainActor
final class SettingsWindow {
    // window is the settings window, nil until first shown.
    private var window: NSWindow?
    // model backs the window's view.
    private let model: SettingsModel

    // init builds the settings window for app.
    init(app: AppDelegate) {
        model = SettingsModel(app: app)
    }

    // show brings the settings window to the front, building it the first time.
    func show() {
        model.reload()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Moorings Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
