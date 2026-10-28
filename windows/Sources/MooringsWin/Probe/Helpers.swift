import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// dragInput presses the keys down, presses the left button at from, moves to to in 20 steps 15 ms
// apart, lets go there, and lets the keys up half a second later, all with SendInput.
func dragInput(from: (x: Int32, y: Int32), to: (x: Int32, y: Int32), keys: [WORD]) {
    for k in keys {
        sendKey(k, up: false)
    }
    sendMouse(from.x, from.y, 0)
    Sleep(100)
    sendMouse(from.x, from.y, 0x0002)
    Sleep(100)
    for i in 1...20 {
        let x = from.x + (to.x - from.x) * Int32(i) / 20, y = from.y + (to.y - from.y) * Int32(i) / 20
        sendMouse(x, y, 0)
        Sleep(15)
    }
    Sleep(200)
    sendMouse(to.x, to.y, 0x0004)
    if !keys.isEmpty {
        Sleep(500)
    }
    for k in keys.reversed() {
        sendKey(k, up: true)
    }
}

// sendMouse moves the pointer to x, y on the virtual desktop with SendInput, adding the button
// flags, 0x0002 for down and 0x0004 for up.
func sendMouse(_ x: Int32, _ y: Int32, _ buttons: DWORD) {
    let left = GetSystemMetrics(SM_XVIRTUALSCREEN), top = GetSystemMetrics(SM_YVIRTUALSCREEN)
    let w = max(2, GetSystemMetrics(SM_CXVIRTUALSCREEN)), h = max(2, GetSystemMetrics(SM_CYVIRTUALSCREEN))
    var input = INPUT()
    input.type = DWORD(INPUT_MOUSE)
    input.mi.dx = LONG((Int(x - left) * 65535) / Int(w - 1))
    input.mi.dy = LONG((Int(y - top) * 65535) / Int(h - 1))
    input.mi.dwFlags = 0x0001 | 0x8000 | 0x4000 | buttons
    _ = SendInput(1, &input, Int32(MemoryLayout<INPUT>.size))
}

// sendKey sends one key down or up with SendInput.
func sendKey(_ vk: WORD, up: Bool) {
    var input = INPUT()
    input.type = DWORD(INPUT_KEYBOARD)
    input.ki.wVk = vk
    input.ki.dwFlags = up ? 0x0002 : 0
    _ = SendInput(1, &input, Int32(MemoryLayout<INPUT>.size))
}

// integrity names the mandatory integrity level of pid's token: low, medium, high or system, or
// unknown when the token cannot be read, as a higher level's token cannot from a lower one.
func integrity(_ pid: DWORD) -> String {
    guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else {
        return "unknown"
    }
    defer { _ = CloseHandle(process) }
    var token: HANDLE?
    guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token), let token else { return "unknown" }
    defer { _ = CloseHandle(token) }
    var size: DWORD = 0
    _ = GetTokenInformation(token, TokenIntegrityLevel, nil, 0, &size)
    guard size > 0 else { return "unknown" }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { buffer.deallocate() }
    guard GetTokenInformation(token, TokenIntegrityLevel, buffer, size, &size) else { return "unknown" }
    let label = buffer.load(as: TOKEN_MANDATORY_LABEL.self)
    guard let sid = label.Label.Sid, let count = GetSidSubAuthorityCount(sid)?.pointee, count > 0,
        let rid = GetSidSubAuthority(sid, DWORD(count) - 1)?.pointee
    else { return "unknown" }
    switch rid {
    case ..<0x2000: return "low"
    case ..<0x3000: return "medium"
    case ..<0x4000: return "high"
    default: return "system"
    }
}

// pump dispatches the thread's messages until until, passing each to each first.
func pump(until: Double, _ each: (MSG) -> Void = { _ in }) {
    let stop = SetTimer(nil, 0, UINT(max(1, ((until - App.now) * 1000).rounded(.up))), nil)
    defer { _ = KillTimer(nil, stop) }
    var msg = MSG()
    while GetMessageW(&msg, nil, 0, 0) {
        if msg.message == UINT(WM_TIMER), msg.hwnd == nil, msg.wParam == stop {
            return
        }
        each(msg)
        _ = TranslateMessage(&msg)
        _ = DispatchMessageW(&msg)
    }
}

// foreground names the foreground window the way the list probe names windows.
func foreground() -> String {
    GetForegroundWindow().map { hex(WinWindows.id($0)) } ?? "none"
}

// bringForward makes hwnd the foreground window. Windows lets only the foreground process do that,
// so when the plain call is refused it joins the foreground thread's input and asks again.
@discardableResult
func bringForward(_ hwnd: HWND) -> Bool {
    if SetForegroundWindow(hwnd) {
        return true
    }
    guard let fg = GetForegroundWindow() else { return false }
    let theirs = GetWindowThreadProcessId(fg, nil), mine = GetCurrentThreadId()
    _ = AttachThreadInput(mine, theirs, true)
    defer { _ = AttachThreadInput(mine, theirs, false) }
    return SetForegroundWindow(hwnd)
}

// press injects the keys down in order and up in reverse, and returns how many events Windows
// took. Arrow keys are sent as extended keys, as a keyboard sends them.
func press(_ keys: [WORD]) -> UINT {
    let key = { (vk: WORD, up: Bool) -> INPUT in
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = vk
        let extended: DWORD = (0x21...0x2E).contains(vk) ? 0x0001 : 0
        input.ki.dwFlags = extended | (up ? 0x0002 : 0)
        return input
    }
    var inputs = keys.map { key($0, false) } + keys.reversed().map { key($0, true) }
    return SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
}

// hex formats a window id the way the list probe does.
func hex(_ id: WindowID) -> String {
    "0x" + String(id, radix: 16)
}

// stamp formats a time to the millisecond.
func stamp(_ t: Double) -> String {
    String(format: "%.3f", t)
}

// pixels formats f as whole x, y, w and h, the same in every locale.
func pixels(_ f: Frame) -> String {
    "\(Int(f.x)) \(Int(f.y)) \(Int(f.w)) \(Int(f.h))"
}

// Monitor is one display as Windows reports it, in top-left physical pixels.
struct Monitor {
    // taskbar is the height a sized monitor keeps for the taskbar, the Windows 11 default at 100
    // percent.
    static let taskbar = 48.0
    // fake stands in for every attached monitor when set, as --screen sets it.
    nonisolated(unsafe) static var fake: Monitor?

    // full is rcMonitor, the whole display.
    var full: Frame
    // usable is rcWork, the display without the taskbar.
    var usable: Frame
    // primary is true for the display that holds the origin.
    var primary: Bool

    // sized returns one primary monitor at the origin of size, with the taskbar along its bottom.
    static func sized(_ size: Size) -> Monitor {
        let full = Frame(x: 0, y: 0, w: Double(size.w), h: Double(size.h))
        let usable = Frame(x: 0, y: 0, w: full.w, h: max(1, full.h - taskbar))
        return Monitor(full: full, usable: usable, primary: true)
    }

    // all returns every monitor in EnumDisplayMonitors order, or the fake one alone when set.
    static func all() -> [Monitor] {
        if let fake {
            return [fake]
        }
        let found = MonitorList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumDisplayMonitors(
            nil, nil,
            { handle, _, _, context in
                let raw = UnsafeRawPointer(bitPattern: Int(context))!
                let found = Unmanaged<MonitorList>.fromOpaque(raw).takeUnretainedValue()
                var info = MONITORINFO()
                info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
                if GetMonitorInfoW(handle, &info) {
                    let primary = info.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0
                    let full = Frame(info.rcMonitor), usable = Frame(info.rcWork)
                    found.monitors.append(Monitor(full: full, usable: usable, primary: primary))
                }
                return true
            }, context)
        return withExtendedLifetime(found) { found.monitors }
    }
}

// MonitorList collects monitors inside the EnumDisplayMonitors callback.
final class MonitorList {
    // monitors holds the monitors found so far.
    var monitors: [Monitor] = []
}

extension Frame {
    // init converts a Win32 RECT.
    init(_ r: RECT) {
        self.init(
            x: Double(r.left), y: Double(r.top), w: Double(r.right - r.left),
            h: Double(r.bottom - r.top))
    }
}
