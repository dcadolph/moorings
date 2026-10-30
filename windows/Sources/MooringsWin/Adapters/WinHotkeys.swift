import Foundation
import WinSDK

import MooringsCore

// WinHotkeys registers the window action shortcuts with RegisterHotKey for the thread that runs
// the message loop, which then receives WM_HOTKEY for each press.
final class WinHotkeys {
    // keyCodes maps each key name to its virtual key code. Delete is Backspace, the key a Mac
    // keyboard labels delete, and forwarddelete is Delete.
    static let keyCodes: [String: UINT] = {
        var out: [String: UINT] = [
            "=": 0xBB, "-": 0xBD, "[": 0xDB, "]": 0xDD, ";": 0xBA, "'": 0xDE, ",": 0xBC, ".": 0xBE,
            "/": 0xBF, "\\": 0xDC, "`": 0xC0, "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
            "return": 0x0D, "enter": 0x0D, "delete": 0x08, "forwarddelete": 0x2E, "escape": 0x1B,
            "tab": 0x09, "space": 0x20, "home": 0x24, "end": 0x23, "pageup": 0x21, "pagedown": 0x22,
        ]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            out[String(c)] = UINT(0x41 + i)
        }
        for i in 0...9 {
            out["\(i)"] = UINT(0x30 + i)
        }
        for i in 1...20 {
            out["f\(i)"] = UINT(0x6F + i)
        }
        return out
    }()
    // modifierFlags maps each modifier to its RegisterHotKey flag. Command is the Windows key.
    static let modifierFlags: [Modifier: UINT] = [
        .alt: 0x0001, .ctrl: 0x0002, .shift: 0x0004, .cmd: 0x0008,
    ]
    // noRepeat is MOD_NOREPEAT, so holding a chord runs its action once.
    static let noRepeat: UINT = 0x4000
    // alreadyRegistered is ERROR_HOTKEY_ALREADY_REGISTERED.
    static let alreadyRegistered: DWORD = 1409
    // arrows are the arrow keys, which the shell owns with the Windows key alone or with Shift.
    static let arrows: Set = ["left", "right", "up", "down"]
    // keyNames maps a key name to the name printed on a Windows keyboard.
    private static let keyNames: [String: String] = [
        "left": "Left", "right": "Right", "up": "Up", "down": "Down", "return": "Enter",
        "enter": "Enter", "delete": "Backspace", "forwarddelete": "Delete", "escape": "Esc",
        "tab": "Tab", "space": "Space", "home": "Home", "end": "End", "pageup": "Page Up",
        "pagedown": "Page Down",
    ]
    // modifierNames maps each modifier to the name printed on a Windows keyboard.
    private static let modifierNames: [Modifier: String] = [
        .ctrl: "Ctrl", .alt: "Alt", .shift: "Shift", .cmd: "Win",
    ]

    // run is called with the action name of a pressed shortcut.
    private let run: (String) -> Void
    // names maps each registered hotkey id to its action name.
    private(set) var names: [Int32: String] = [:]
    // skipped lists each shortcut not registered by action name, with the reason.
    private(set) var skipped: [(name: String, reason: String)] = []
    // pressed lists the action names of the presses received, in order.
    private(set) var pressed: [String] = []
    // grabBase is the first hotkey id of the grabbed keys, clear of the shortcut ids.
    static let grabBase: Int32 = 0x8000
    // grabTags maps each grabbed key's id to its tag.
    private var grabTags: [Int32: String] = [:]
    // grabHandler is called with the tag of a pressed grabbed key, nil while nothing is grabbed.
    private var grabHandler: ((String) -> Void)?

    // claimBase is the first hotkey id of the claimed keys, clear of the shortcut and grab ids and
    // under 0xC000, the top of the range RegisterHotKey allows an application.
    static let claimBase: Int32 = 0xA000
    // claimTags maps each claimed key's id to its tag.
    private var claimTags: [Int32: String] = [:]
    // claimHandler is called with the tag of a pressed claimed key, nil while nothing is claimed.
    private var claimHandler: ((String) -> Void)?

    // init builds hotkeys that call run with the action name of each press.
    init(run: @escaping (String) -> Void) {
        self.run = run
    }

    // spelled returns the shortcut the way Windows writes one, such as Ctrl+Alt+Left.
    static func spelled(_ sc: Shortcut) -> String {
        let key = keyNames[sc.key] ?? sc.key.uppercased()
        return (sc.mods.compactMap { modifierNames[$0] } + [key]).joined(separator: "+")
    }

    // shellOwns reports whether Windows keeps sc for itself: the Windows key with an arrow, alone
    // or with Shift, snaps and moves windows between displays.
    static func shellOwns(_ sc: Shortcut) -> Bool {
        sc.mods.contains(.cmd) && !sc.mods.contains(.ctrl) && !sc.mods.contains(.alt)
            && arrows.contains(sc.key)
    }

    // bind registers map, replacing what was bound before. A shortcut whose action Windows cannot
    // run yet, whose key Windows has no code for, that the shell owns, or that another program
    // holds is skipped and logged.
    func bind(_ map: [String: Shortcut], runnable: (String) -> Bool) {
        unbind()
        var id: Int32 = 0
        for (name, sc) in map.sorted(by: { $0.key < $1.key }) {
            guard runnable(name) else {
                skip(name, sc, "not on Windows yet")
                continue
            }
            guard let vk = Self.keyCodes[sc.key] else {
                skip(name, sc, "no such key on Windows")
                continue
            }
            if Self.shellOwns(sc) {
                skip(name, sc, "Windows keeps it")
                continue
            }
            id += 1
            let mods = sc.mods.reduce(Self.noRepeat) { $0 | (Self.modifierFlags[$1] ?? 0) }
            guard RegisterHotKey(nil, id, mods, vk) else {
                let error = GetLastError()
                let held = error == Self.alreadyRegistered
                skip(name, sc, held ? "another program holds it" : "error \(error)")
                continue
            }
            names[id] = name
        }
    }

    // unbind removes every registered shortcut.
    func unbind() {
        for id in names.keys {
            _ = UnregisterHotKey(nil, id)
        }
        names = [:]
        skipped = []
    }

    // grab registers each key until ungrab, so its presses go to handler by tag instead of the front
    // program. It returns how many keys registered; a key another program holds is skipped. A second
    // grab replaces the first.
    @discardableResult
    func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        ungrab()
        grabHandler = handler
        for (i, k) in keys.enumerated() {
            guard let vk = Self.keyCodes[k.key] else { continue }
            let id = Self.grabBase + Int32(i)
            let mods = k.modifiers.shortcut.reduce(Self.noRepeat) { $0 | (Self.modifierFlags[$1] ?? 0) }
            guard RegisterHotKey(nil, id, mods, vk) else { continue }
            grabTags[id] = k.tag
        }
        return grabTags.count
    }

    // ungrab removes every grabbed key.
    func ungrab() {
        for id in grabTags.keys {
            _ = UnregisterHotKey(nil, id)
        }
        grabTags = [:]
        grabHandler = nil
    }

    // claim registers each key until unclaim, so its presses go to handler by tag whatever is grabbed
    // or bound. It returns how many keys registered; a key another program holds is skipped. A second
    // claim replaces the first.
    @discardableResult
    func claim(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        unclaim()
        claimHandler = handler
        for (i, k) in keys.enumerated() {
            guard let vk = Self.keyCodes[k.key] else { continue }
            let id = Self.claimBase + Int32(i)
            let mods = k.modifiers.shortcut.reduce(Self.noRepeat) { $0 | (Self.modifierFlags[$1] ?? 0) }
            guard RegisterHotKey(nil, id, mods, vk) else { continue }
            claimTags[id] = k.tag
        }
        return claimTags.count
    }

    // unclaim removes every claimed key.
    func unclaim() {
        for id in claimTags.keys {
            _ = UnregisterHotKey(nil, id)
        }
        claimTags = [:]
        claimHandler = nil
    }

    // fire runs the action of the hotkey a WM_HOTKEY message names, or hands a claimed or grabbed
    // key's tag to its handler.
    func fire(_ wParam: WPARAM) {
        let id = Int32(truncatingIfNeeded: wParam)
        if let tag = claimTags[id] {
            claimHandler?(tag)
            return
        }
        if let tag = grabTags[id] {
            grabHandler?(tag)
            return
        }
        guard let name = names[id] else { return }
        pressed.append(name)
        run(name)
    }

    // skip records name's shortcut sc as not registered and logs why.
    private func skip(_ name: String, _ sc: Shortcut, _ reason: String) {
        skipped.append((name, reason))
        let line = "hotkeys: \(name) \(Self.spelled(sc)) skipped: \(reason)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
