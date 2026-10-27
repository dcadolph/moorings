import AppKit
import SwiftUI

import MooringsCore

// ShortcutRecorder is a button that records the next key press with at least one modifier as a
// shortcut. Escape cancels. The window shortcuts are off while it records, so the press reaches it.
struct ShortcutRecorder: View {
    // current is the shortcut in effect, nil when the action has none.
    let current: Shortcut?
    // suspend turns the window shortcuts off while recording, and on again after.
    let suspend: (Bool) -> Void
    // record is told the recorded shortcut.
    let record: (StoredShortcut) -> Void

    // recording reports whether the next key press is being recorded.
    @State private var recording = false
    // monitor is the local key monitor while recording.
    @State private var monitor: Any?

    // body shows the shortcut, or a prompt while recording.
    var body: some View {
        Button(recording ? "Press keys…" : current?.text ?? "Record") {
            recording ? stop() : start()
        }
        .frame(minWidth: 110)
        .onDisappear {
            if recording {
                stop()
            }
        }
        .help(current.map { "Click, then press a new shortcut for \($0.spelled). Escape cancels." }
            ?? "Click, then press a shortcut with at least one modifier. Escape cancels.")
    }

    // start begins recording in the key window. A key pressed in any other window ends the recording
    // and goes to that window, so closing Settings mid-recording never leaves keys being eaten.
    private func start() {
        suspend(true)
        recording = true
        let window = NSApp.keyWindow
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window, window?.isVisible == true else {
                stop()
                return event
            }
            if event.keyCode == 53 {
                stop()
                return nil
            }
            guard let sc = Self.shortcut(event) else {
                NSSound.beep()
                return nil
            }
            record(sc)
            stop()
            return nil
        }
    }

    // stop ends recording.
    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
        suspend(false)
    }

    // names maps each virtual key code to its key name.
    static let names: [Int: String] = Dictionary(Hotkeys.keyCodes.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })

    // shortcut returns the shortcut event presses, nil without a modifier or for an unknown key.
    static func shortcut(_ event: NSEvent) -> StoredShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: [String] = []
        if flags.contains(.control) { mods.append("ctrl") }
        if flags.contains(.option) { mods.append("alt") }
        if flags.contains(.shift) { mods.append("shift") }
        if flags.contains(.command) { mods.append("cmd") }
        guard !mods.isEmpty, let key = names[Int(event.keyCode)] else { return nil }
        return StoredShortcut(mods: mods, key: key)
    }
}
