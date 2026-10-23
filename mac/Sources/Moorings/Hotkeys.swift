import Carbon.HIToolbox
import os

import MooringsCore

// Hotkeys registers the window action shortcuts with Carbon, so they work without an event tap.
@MainActor
final class Hotkeys {
    // signature tags the hotkeys moorings registers.
    static let signature: OSType = 0x4D52_4E47
    // keyCodes maps each key name to its virtual key code.
    static let keyCodes: [String: Int] = {
        var out: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9, "=": kVK_ANSI_Equal, "-": kVK_ANSI_Minus, "[": kVK_ANSI_LeftBracket,
            "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma,
            ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "return": kVK_Return, "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
            "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space, "home": kVK_Home, "end": kVK_End,
            "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        ]
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fkeys.enumerated() {
            out["f\(i + 1)"] = code
        }
        return out
    }()

    // current is the one Hotkeys the Carbon handler reports to.
    nonisolated(unsafe) static weak var current: Hotkeys?

    // logger writes binding problems to the unified log.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "hotkeys")
    // run is called with the action name of a pressed shortcut.
    private let run: @MainActor (String) -> Void
    // refs holds each registered hotkey.
    private var refs: [EventHotKeyRef] = []
    // names maps each hotkey id to its action name.
    private var names: [UInt32: String] = [:]
    // handler is the installed Carbon event handler.
    private var handler: EventHandlerRef?
    // enabled reports whether the shortcuts are registered. While off their keys reach the front app.
    private(set) var enabled = true
    // map is the shortcuts last bound, registered again when the shortcuts are turned back on.
    private var map: [String: Shortcut] = [:]

    // init installs the Carbon handler that reports presses to run.
    init(run: @escaping @MainActor (String) -> Void) {
        self.run = run
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == Hotkeys.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Hotkeys.current?.pressed(id.id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    // bind replaces every registered hotkey with the shortcuts in map and returns the problems.
    @discardableResult
    func bind(_ map: [String: Shortcut]) -> [String] {
        self.map = map
        unregister()
        guard enabled else { return [] }
        var problems: [String] = []
        for (i, (name, sc)) in map.sorted(by: { $0.key < $1.key }).enumerated() {
            guard let code = Self.keyCodes[sc.key.lowercased()] else {
                problems.append("shortcut for \(name) has an unknown key \(sc.key): ignoring it")
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i + 1))
            let status = RegisterEventHotKey(UInt32(code), Self.modifiers(sc.mods), id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                problems.append("shortcut for \(name) could not be registered: \(sc.text) may be taken")
                continue
            }
            refs.append(ref)
            names[id.id] = name
        }
        for p in problems {
            logger.notice("\(p, privacy: .public)")
        }
        return problems
    }

    // setEnabled registers the shortcuts again, or unregisters them so their keys reach the front app.
    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            bind(map)
        } else {
            unregister()
        }
    }

    // unregister removes every registered hotkey.
    private func unregister() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs = []
        names = [:]
    }

    // pressed runs the action for the hotkey with id.
    private func pressed(_ id: UInt32) {
        guard let name = names[id] else { return }
        run(name)
    }

    // modifiers returns the Carbon modifier mask for mods.
    static func modifiers(_ mods: [Modifier]) -> UInt32 {
        var out = 0
        for m in mods {
            switch m {
            case .ctrl: out |= controlKey
            case .alt: out |= optionKey
            case .shift: out |= shiftKey
            case .cmd: out |= cmdKey
            }
        }
        return UInt32(out)
    }
}
