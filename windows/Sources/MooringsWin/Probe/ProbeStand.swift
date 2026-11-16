import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// standClass is the window class of the stand probe's window.
let standClass = "MooringsStandIn"

// StandEdit holds the stand probe's Edit control under --edit for the window procedure.
enum StandEdit {
    // edit is the Edit control, which fills the window and takes the focus whenever the window does.
    nonisolated(unsafe) static var edit: HWND?
}

// probeStand shows a captioned window that accepts any size for the given seconds, then closes. Windows
// caps a window that leaves its size limits to the default at the desktop plus its border, 1044 by 788
// on the runner, so Notepad cannot take a 3440x1440 slot there. This window answers WM_GETMINMAXINFO
// with no cap, as every window on a real ultrawide is capped past its size, and stands in for the
// app under the fake ultrawide. Under --edit an Edit control fills the window and holds its focus, so
// the cycle probe can read where a word move left the caret in another process.
func probeStand(_ opts: ProbeOptions) -> Int32 {
    let instance = GetModuleHandleW(nil)
    var wc = WNDCLASSEXW()
    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wc.hInstance = instance
    wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
        switch msg {
        case UINT(WM_GETMINMAXINFO):
            if let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(lParam)) {
                info.pointee.ptMaxTrackSize = POINT(x: 32000, y: 32000)
                info.pointee.ptMaxSize = POINT(x: 32000, y: 32000)
            }
            return 0
        case UINT(WM_SETFOCUS) where StandEdit.edit != nil:
            _ = SetFocus(StandEdit.edit)
            return 0
        case UINT(WM_SIZE) where StandEdit.edit != nil:
            var r = RECT()
            _ = GetClientRect(hwnd, &r)
            _ = MoveWindow(StandEdit.edit, 0, 0, r.right, r.bottom, true)
            return 0
        case UINT(WM_DESTROY):
            PostQuitMessage(0)
            return 0
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }
    let name = wide(standClass)
    let registered = name.withUnsafeBufferPointer { buffer in
        wc.lpszClassName = buffer.baseAddress
        return RegisterClassExW(&wc) != 0
    }
    guard registered else {
        print("stand: class not registered: \(GetLastError())")
        return 1
    }
    // 0x00CF0000 is WS_OVERLAPPEDWINDOW and 0x10000000 is WS_VISIBLE.
    let style: DWORD = 0x00CF_0000 | 0x1000_0000
    guard
        let hwnd = CreateWindowExW(
            0, name, wide("Moorings stand-in"), style, 100, 100, 600, 400, nil, nil,
            instance, nil)
    else {
        print("stand: no window: \(GetLastError())")
        return 1
    }
    if opts.edit {
        // 0x40000000 is WS_CHILD and 0x0080 is ES_AUTOHSCROLL.
        guard
            let edit = CreateWindowExW(
                0, wide("EDIT"), nil, 0x4000_0000 | 0x1000_0000 | 0x0080, 0, 0, 100, 100, hwnd, nil, instance, nil)
        else {
            print("stand: no edit control: \(GetLastError())")
            return 1
        }
        StandEdit.edit = edit
        var r = RECT()
        _ = GetClientRect(hwnd, &r)
        _ = MoveWindow(edit, 0, 0, r.right, r.bottom, true)
        _ = SetFocus(edit)
    }
    print("stand: \(hex(WinWindows.id(hwnd))) pid \(GetCurrentProcessId())")
    pump(until: App.now + opts.seconds)
    if IsWindow(hwnd) {
        _ = DestroyWindow(hwnd)
    }
    return 0
}
