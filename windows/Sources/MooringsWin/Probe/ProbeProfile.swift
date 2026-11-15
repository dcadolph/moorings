import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeProfile saves two profiles on a fresh choices file, Halves with the default shortcuts and Few
// with left-half and right-half cleared, and switches to Halves, Few and Halves again through the
// engine's profile actions. After each switch it prints the active profile, how many shortcuts the
// hotkeys hold, and whether left-half is among them, then prints the Profiles folder.
func probeProfile(_ opts: ProbeOptions) -> Int32 {
    var few = ProfileSettings()
    few.shortcuts.updateValue(nil, forKey: "left-half")
    few.shortcuts.updateValue(nil, forKey: "right-half")
    var choices = Choices()
    choices.profiles = [Profile(name: "Halves"), Profile(name: "Few", settings: few)]
    guard let made = probeApp(choices, opts, "profile") else { return 1 }
    let (app, file) = made
    defer { removeProbeStore(file) }
    for name in ["Halves", "Few", "Halves"] {
        let ran = app.engine.actions.run(Profile.prefix + name)
        let names = app.hotkeys.names.values
        print(
            "\(name): ran \(ran) active \(app.engine.anchors.choices.activeProfile ?? "none") bound \(names.count)"
                + " left-half \(names.contains("left-half"))")
    }
    printMenu([Tray.profilesFolder(choices: app.engine.anchors.choices)])
    app.hotkeys.unbind()
    return 0
}

// probeImport imports two settings files through the tray on a fresh choices file. The first is not
// JSON, the control: it must be refused and leave the choices file's bytes as they were. The second is
// a Mac export held here, with Mac-only keys this build does not know, that anchors the app's window
// in the left top slot at strip widths 30 and 25 with slot stacks off. After a pass it prints the
// imported widths and the window's frame beside the left strip those widths give.
func probeImport(_ opts: ProbeOptions) -> Int32 {
    guard let made = probeApp(Choices(), opts, "import") else { return 1 }
    let (app, file) = made
    defer { removeProbeStore(file) }
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let pad = app.windows.scan(screens, full: true).windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let wide = screens.hostFrame
    else {
        print("import: no window of \(opts.app) or no host display")
        return 1
    }
    let tray = Tray(app: app)
    app.notify = { title, body in print("notice: \(title): \(body)") }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
    let bad = dir.appendingPathComponent("moorings-import-bad-\(UUID().uuidString).json")
    let mac = dir.appendingPathComponent("moorings-import-mac-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: bad)
        try? FileManager.default.removeItem(at: mac)
    }
    let export = """
        {"app": "moorings", "version": 1, "exported": "2026-11-01T12:00:00Z", "settings": {
          "slots": {"left-top": "\(pad.bundle.replacingOccurrences(of: "\\", with: "\\\\"))",
            "right-top": "com.apple.TextEdit"},
          "widths": {"left": 30, "right": 25}, "slotStacks": false, "keymap": "rectangle",
          "menuBarIcon": "anchor", "dockIcon": false, "launchAtLogin": true}}
        """
    do {
        try Data("{ not json".utf8).write(to: bad)
        try Data(export.utf8).write(to: mac)
    } catch {
        print("import: \(error)")
        return 1
    }
    let before = try? Data(contentsOf: file)
    let refused = !tray.importSettings(from: bad.path)
    let after = try? Data(contentsOf: file)
    print("invalid: refused \(refused) file unchanged \(before != nil && before == after)")
    app.windows.move(pad.id, to: Frame(x: wide.x + wide.w / 2 - 250, y: wide.y + 150, w: 500, h: 350))
    let took = tray.importSettings(from: mac.path)
    app.run(until: App.now + 2)
    let w = app.engine.anchors.choices.widths ?? Widths(left: 0, right: 0)
    print("mac: imported \(took) widths \(Int(w.left)) \(Int(w.right))")
    let strip = Geometry.regions(wide, w.left, w.right).left
    print("strip: want \(pixels(strip)) got \(app.windows.frame(pad.id).map(pixels) ?? "none")")
    return 0
}

// probeApp saves choices to a fresh temporary file and builds an app on it, printing why under label
// when the save fails.
private func probeApp(_ choices: Choices, _ opts: ProbeOptions, _ label: String) -> (App, URL)? {
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-\(label)-\(UUID().uuidString).json")
    let store = Store(url: file)
    do {
        try store.save(choices)
    } catch {
        print("\(label): \(error)")
        return nil
    }
    return (App(store: store, minAspect: opts.minAspect), file)
}

// removeProbeStore deletes a probe's choices file and the copy load set aside.
private func removeProbeStore(_ file: URL) {
    try? FileManager.default.removeItem(at: file)
    try? FileManager.default.removeItem(at: Store(url: file).aside)
}
