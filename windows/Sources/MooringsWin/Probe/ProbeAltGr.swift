import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// altGrClass is the window class of the altgr probe's stand-in.
let altGrClass = "MooringsAltGrStandIn"
// altGrGerman is the German layout's id, on which AltGr and E type the euro sign.
let altGrGerman = "00000407"
// altGrUS is the US layout's id, which has no AltGr, so right Alt is a plain Alt.
let altGrUS = "00000409"

// AltGrStand holds the altgr probe's Edit control for the stand-in's window procedure.
enum AltGrStand {
    // edit is the stand-in's Edit control, which takes the focus whenever its window does.
    nonisolated(unsafe) static var edit: HWND?
}

// AltGrPhase is one press the altgr probe makes.
struct AltGrPhase {
    // name labels the phase's lines.
    let name: String
    // layout is the layout id the stand-in's thread switches to before the keys go.
    let layout: String
    // keys are pressed in order and released in reverse, by scan code, each marked when it is an
    // extended key as right Alt is.
    let keys: [(scan: WORD, extended: Bool)]
}

// altGrPhases are German right Alt and E, which types the euro sign, German left Ctrl, left Alt and E,
// which runs the shortcut, and US left Ctrl, right Alt and E, which has no AltGr and runs it too.
let altGrPhases = [
    AltGrPhase(name: "altgr", layout: altGrGerman, keys: [(0x38, true), (0x12, false)]),
    AltGrPhase(name: "ctrl-alt", layout: altGrGerman, keys: [(0x1D, false), (0x38, false), (0x12, false)]),
    AltGrPhase(name: "us", layout: altGrUS, keys: [(0x1D, false), (0x38, true), (0x12, false)]),
]

// probeAltGr binds the shortcuts from a fresh choices file with German loaded, so Ctrl+Alt+E is
// first-two-thirds, opens a stand-in with an Edit control on this thread, and runs the loop while a
// second thread makes each phase's press. Each phase prints its layout, the Edit's text and the
// stand-in's frame. Then it prints the presses received and the shortcuts given up section of the
// report Save a report would write now.
func probeAltGr(_ opts: ProbeOptions) -> Int32 {
    AltGr.on = !opts.noAltGr
    let original = GetKeyboardLayout(0)
    let before = Set(AltGr.installed().map { AltGr.name($0) })
    let loaded = [altGrGerman, altGrUS].map { LoadKeyboardLayoutW(wide($0), 0) }
    defer {
        _ = ActivateKeyboardLayout(original, 0)
        for layout in loaded where !before.contains(AltGr.name(layout)) {
            _ = UnloadKeyboardLayout(layout)
        }
    }
    print("layouts: \(AltGr.installed().map { AltGr.name($0) }.joined(separator: " "))")
    guard let stand = altGrStandIn() else { return 1 }
    defer { _ = DestroyWindow(stand.top) }
    _ = ActivateKeyboardLayout(loaded[0], 0)
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("altgr: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let map = Bindings(app.engine.anchors.choices).map
    app.hotkeys.bind(map, runnable: app.engine.actions.supports)
    defer { app.hotkeys.unbind() }
    print("altgr rule: \(AltGr.on ? "on" : "off")")
    print("table: \(map.count) registered: \(app.hotkeys.names.count) skipped: \(app.hotkeys.skipped.count)")
    for s in app.hotkeys.skipped {
        print("skipped \(s.name): \(s.reason)")
    }
    print("chord: first-two-thirds \(map["first-two-thirds"].map(WinHotkeys.spelled) ?? "none")")
    _ = bringForward(stand.top)
    print("foreground: \(GetForegroundWindow() == stand.top)")
    var r = RECT()
    _ = GetWindowRect(stand.top, &r)
    let start = (x: r.left, y: r.top, w: r.right - r.left, h: r.bottom - r.top)
    print("start: \(start.x) \(start.y) \(start.w) \(start.h)")
    let loop = GetCurrentThreadId()
    let topBits = UInt(bitPattern: stand.top), editBits = UInt(bitPattern: stand.edit)
    Thread {
        Sleep(1000)
        for phase in altGrPhases {
            guard let top = HWND(bitPattern: topBits), let edit = HWND(bitPattern: editBits) else { break }
            runAltGrPhase(phase, top: top, edit: edit, start: start)
        }
        _ = PostThreadMessageW(loop, UINT(WM_QUIT), 0, 0)
    }.start()
    app.run(until: App.now + opts.seconds)
    let pressed = app.hotkeys.pressed
    print("hotkeys received: \(pressed.isEmpty ? "none" : pressed.joined(separator: ","))")
    for line in reportShortcuts(app) {
        print("report: \(line)")
    }
    return 0
}

// reportShortcuts returns the lines Save a report would write for app now, from its shortcuts given
// up header to the line before its choices header.
func reportShortcuts(_ app: App) -> [String] {
    let lines = Report.text(app, at: Date()).split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
    guard let from = lines.firstIndex(of: "shortcuts given up:") else { return [] }
    return Array(lines[from...].prefix { !$0.hasPrefix("choices: ") })
}

// altGrStandIn opens the probe's stand-in on this thread: a captioned window at 200 150 500 350 whose
// client is one Edit control holding the focus. It returns both, nil when either is refused.
func altGrStandIn() -> (top: HWND, edit: HWND)? {
    let instance = GetModuleHandleW(nil)
    var wc = WNDCLASSEXW()
    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wc.hInstance = instance
    wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
        switch msg {
        case UINT(WM_SETFOCUS):
            if let edit = AltGrStand.edit {
                _ = SetFocus(edit)
            }
            return 0
        case UINT(WM_SIZE):
            if let edit = AltGrStand.edit {
                var r = RECT()
                _ = GetClientRect(hwnd, &r)
                _ = MoveWindow(edit, 0, 0, r.right, r.bottom, true)
            }
            return 0
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }
    let name = wide(altGrClass)
    let registered = name.withUnsafeBufferPointer { buffer in
        wc.lpszClassName = buffer.baseAddress
        return RegisterClassExW(&wc) != 0
    }
    guard registered else {
        print("altgr: class not registered: \(GetLastError())")
        return nil
    }
    // 0x00CF0000 is WS_OVERLAPPEDWINDOW and 0x10000000 is WS_VISIBLE.
    guard
        let top = CreateWindowExW(
            0, name, wide("Moorings AltGr stand-in"), 0x00CF_0000 | 0x1000_0000, 200, 150, 500, 350, nil, nil,
            instance, nil)
    else {
        print("altgr: no window: \(GetLastError())")
        return nil
    }
    // 0x40000000 is WS_CHILD and 0x0080 is ES_AUTOHSCROLL.
    guard
        let edit = CreateWindowExW(
            0, wide("EDIT"), nil, 0x4000_0000 | 0x1000_0000 | 0x0080, 0, 0, 100, 100, top, nil, instance, nil)
    else {
        print("altgr: no edit control: \(GetLastError())")
        _ = DestroyWindow(top)
        return nil
    }
    AltGrStand.edit = edit
    var r = RECT()
    _ = GetClientRect(top, &r)
    _ = MoveWindow(edit, 0, 0, r.right, r.bottom, true)
    _ = SetFocus(edit)
    print("stand-in: \(hex(WinWindows.id(top))) edit \(hex(WinWindows.id(edit)))")
    return (top, edit)
}

// runAltGrPhase puts the stand-in back at start with an empty Edit, switches its thread to the phase's
// layout, holds the phase's keys for 0.4 s, gives the loop 1.2 s, and prints the layout, whether the
// stand-in was in front, the Edit's text as code points, and the stand-in's frame.
func runAltGrPhase(_ phase: AltGrPhase, top: HWND, edit: HWND, start: (x: Int32, y: Int32, w: Int32, h: Int32)) {
    // 0x0014 is SWP_NOZORDER and SWP_NOACTIVATE.
    _ = SetWindowPos(top, nil, start.x, start.y, start.w, start.h, 0x0014)
    var empty: [WCHAR] = [0]
    _ = empty.withUnsafeMutableBufferPointer { buffer in
        SendMessageW(edit, UINT(WM_SETTEXT), 0, LPARAM(Int(bitPattern: buffer.baseAddress)))
    }
    let layout = LoadKeyboardLayoutW(wide(phase.layout), 0)
    _ = SendMessageW(top, UINT(WM_INPUTLANGCHANGEREQUEST), 0, LPARAM(Int(bitPattern: layout)))
    if GetForegroundWindow() != top {
        _ = bringForward(top)
    }
    Sleep(300)
    print("\(phase.name) layout: \(AltGr.name(GetKeyboardLayout(GetWindowThreadProcessId(top, nil))))")
    print("\(phase.name) foreground: \(GetForegroundWindow() == top)")
    let down = altGrKeys(phase.keys, up: false)
    Sleep(400)
    let up = altGrKeys(Array(phase.keys.reversed()), up: true)
    print("\(phase.name) sent: \(down + up)")
    Sleep(1200)
    var buffer = [WCHAR](repeating: 0, count: 64)
    let n = buffer.withUnsafeMutableBufferPointer { b in
        SendMessageW(edit, UINT(WM_GETTEXT), WPARAM(b.count), LPARAM(Int(bitPattern: b.baseAddress)))
    }
    let text = String(decoding: buffer.prefix(max(0, Int(n))), as: UTF16.self)
    print("\(phase.name) text: \(text.isEmpty ? "empty" : AltGr.codes(text))")
    var r = RECT()
    _ = GetWindowRect(top, &r)
    print("\(phase.name) frame: \(r.left) \(r.top) \(r.right - r.left) \(r.bottom - r.top)")
}

// altGrKeys sends keys by scan code with SendInput, all down or all up, and returns how many events
// Windows took.
func altGrKeys(_ keys: [(scan: WORD, extended: Bool)], up: Bool) -> UINT {
    var inputs = keys.map { key -> INPUT in
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wScan = key.scan
        // 0x0008 is KEYEVENTF_SCANCODE, 0x0001 KEYEVENTF_EXTENDEDKEY and 0x0002 KEYEVENTF_KEYUP.
        input.ki.dwFlags = 0x0008 | (key.extended ? 0x0001 : 0) | (up ? 0x0002 : 0)
        return input
    }
    return SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
}
