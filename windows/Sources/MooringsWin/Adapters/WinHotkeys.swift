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
    // typed lists each chord AltGr typed a character through instead of running, once per chord,
    // layout and character, and says so when the character may not have arrived.
    private(set) var typed: [String] = []
    // chords maps each registered hotkey id to its shortcut and key code.
    private var chords: [Int32: (shortcut: Shortcut, vk: UINT)] = [:]
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
    // run yet, whose key Windows has no code for, that the shell owns, whose key is a dead key under
    // AltGr on an installed layout, or that another program holds is skipped and logged.
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
            if AltGr.on, let layout = AltGr.deadOn(vk, sc) {
                skip(name, sc, "AltGr makes a dead key with it on layout \(layout)")
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
            chords[id] = (sc, vk)
        }
    }

    // unbind removes every registered shortcut.
    func unbind() {
        for id in names.keys {
            _ = UnregisterHotKey(nil, id)
        }
        names = [:]
        chords = [:]
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
    // key's tag to its handler. A press that is AltGr typing a character in the front window's layout
    // types that character and runs nothing.
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
        if let chord = chords[id], let through = AltGr.through(chord.shortcut, chord.vk) {
            let outranked = AltGr.frontOutranks()
            AltGr.send(through.text)
            note(name, chord.shortcut, through, outranked: outranked)
            return
        }
        pressed.append(name)
        run(name)
    }

    // skip records name's shortcut sc as not registered and logs why.
    private func skip(_ name: String, _ sc: Shortcut, _ reason: String) {
        skipped.append((name, reason))
        let line = "hotkeys: \(name) \(Self.spelled(sc)) skipped: \(reason)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    // note records the first time AltGr typed a character through name's shortcut sc on a layout,
    // and logs it. When outranked is set, the entry says the character may not have arrived.
    private func note(_ name: String, _ sc: Shortcut, _ through: (text: String, layout: String), outranked: Bool) {
        let what = "\(AltGr.codes(through.text)) on layout \(through.layout)"
        let entry =
            outranked
            ? "\(name) \(Self.spelled(sc)) may not have typed \(what): the window in front has higher rights"
                + " or could not be read"
            : "\(name) \(Self.spelled(sc)) typed \(what)"
        guard !typed.contains(entry) else { return }
        typed.append(entry)
        FileHandle.standardError.write(Data("hotkeys: \(entry)\n".utf8))
    }
}

// AltGr reads what a key types with AltGr. Windows sends AltGr as left Ctrl and right Alt, so a
// Ctrl+Alt shortcut would otherwise eat a character the typist's keyboard layout makes with it.
enum AltGr {
    // on is false only in the altgr probe's negative control, which runs every chord as a shortcut.
    nonisolated(unsafe) static var on = true

    // levels orders the integrity levels a process can run at, lowest first.
    static let levels = ["low", "medium", "high", "system"]
    // own is this process's integrity level, read once.
    static let own = integrity(GetCurrentProcessId())

    // Typed is what a key makes with AltGr on one layout.
    enum Typed: Equatable {
        case nothing
        case text(String)
        case dead
    }

    // applies reports whether AltGr can press sc: it holds Ctrl and Alt and not the Windows key.
    static func applies(_ sc: Shortcut) -> Bool {
        sc.mods.contains(.ctrl) && sc.mods.contains(.alt) && !sc.mods.contains(.cmd)
    }

    // typed asks layout what vk makes with AltGr, and Shift when shift is set, without changing the
    // keyboard state a pending dead key leaves. Control characters count as nothing.
    static func typed(_ vk: UINT, shift: Bool, on layout: HKL?) -> Typed {
        var state = [BYTE](repeating: 0, count: 256)
        // 0x11 is VK_CONTROL, 0xA2 VK_LCONTROL, 0x12 VK_MENU and 0xA5 VK_RMENU, the keys AltGr holds.
        for key in [0x11, 0xA2, 0x12, 0xA5] {
            state[key] = 0x80
        }
        if shift {
            // 0x10 is VK_SHIFT and 0xA0 VK_LSHIFT.
            state[0x10] = 0x80
            state[0xA0] = 0x80
        }
        let scan = MapVirtualKeyExW(vk, 0, layout)
        var buffer = [WCHAR](repeating: 0, count: 8)
        // Flag 0x4 leaves the keyboard state alone, so a dead key the typist pressed stays pending.
        let n = ToUnicodeEx(vk, scan, state, &buffer, Int32(buffer.count), 0x4, layout)
        if n < 0 {
            return .dead
        }
        guard n > 0 else { return .nothing }
        let text = String(decoding: buffer.prefix(Int(n)), as: UTF16.self)
        guard text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return .nothing }
        return .text(text)
    }

    // through returns the text sc's key types with AltGr in the front window's layout, and the
    // layout's name, when this press is AltGr typing and not the shortcut. Left Alt down means the
    // shortcut. When both Alt keys are already up, as after a quick tap, the press types.
    static func through(_ sc: Shortcut, _ vk: UINT) -> (text: String, layout: String)? {
        guard on, applies(sc), !leftAltDown else { return nil }
        let layout = front()
        guard case .text(let text) = typed(vk, shift: sc.mods.contains(.shift), on: layout) else { return nil }
        return (text, name(layout))
    }

    // deadOn returns the name of the first installed layout on which sc's key is a dead key under
    // AltGr, nil when there is none. A dead key cannot be typed through, so its chord is not bound.
    static func deadOn(_ vk: UINT, _ sc: Shortcut) -> String? {
        guard applies(sc) else { return nil }
        let shift = sc.mods.contains(.shift)
        return installed().first { typed(vk, shift: shift, on: $0) == .dead }.map { name($0) }
    }

    // frontOutranks reports whether the foreground window's process runs at a higher integrity level
    // than this one, as a window run as administrator does over a standard Moorings. Windows drops
    // input sent to such a window and reports no error. A level that cannot be read counts as higher,
    // since a higher level's token cannot be read from a lower one.
    static func frontOutranks() -> Bool {
        var pid: DWORD = 0
        guard let window = GetForegroundWindow(), GetWindowThreadProcessId(window, &pid) != 0,
            let mine = levels.firstIndex(of: own)
        else { return false }
        guard let theirs = levels.firstIndex(of: integrity(pid)) else { return true }
        return theirs > mine
    }

    // leftAltDown reports whether the left Alt key is down now. AltGr is the right Alt key.
    static var leftAltDown: Bool {
        // 0xA4 is VK_LMENU.
        GetAsyncKeyState(0xA4) < 0
    }

    // front returns the keyboard layout of the thread that owns the foreground window.
    static func front() -> HKL? {
        let thread = GetForegroundWindow().map { GetWindowThreadProcessId($0, nil) } ?? 0
        return GetKeyboardLayout(thread)
    }

    // installed returns every keyboard layout loaded for the session.
    static func installed() -> [HKL?] {
        let count = GetKeyboardLayoutList(0, nil)
        guard count > 0 else { return [] }
        var list = [HKL?](repeating: nil, count: Int(count))
        let n = GetKeyboardLayoutList(count, &list)
        return Array(list.prefix(Int(max(0, n))))
    }

    // name writes layout's handle as eight hex digits, such as 04070407 for German, whose low word
    // is the language.
    static func name(_ layout: HKL?) -> String {
        let digits = String(UInt32(truncatingIfNeeded: Int(bitPattern: layout)), radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    }

    // codes writes text as its code points, such as U+20AC, so a console in any code page prints it.
    static func codes(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            let digits = String(scalar.value, radix: 16, uppercase: true)
            return "U+" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        }.joined(separator: " ")
    }

    // send types text into the focused window as Unicode key events, which no held modifier changes,
    // and returns how many events Windows took.
    @discardableResult
    static func send(_ text: String) -> UINT {
        var inputs: [INPUT] = []
        for unit in text.utf16 {
            for up in [false, true] {
                var input = INPUT()
                input.type = DWORD(INPUT_KEYBOARD)
                input.ki.wScan = unit
                // 0x0004 is KEYEVENTF_UNICODE and 0x0002 KEYEVENTF_KEYUP.
                input.ki.dwFlags = 0x0004 | (up ? 0x0002 : 0)
                inputs.append(input)
            }
        }
        return SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
    }
}
