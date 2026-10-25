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
