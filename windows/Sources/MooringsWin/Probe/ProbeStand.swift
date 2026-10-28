import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// standClass is the window class of the stand probe's window.
let standClass = "MooringsStandIn"

// probeStand shows a captioned window that accepts any size for the given seconds, then closes. Windows
// caps a window that leaves its size limits to the default at the desktop plus its border, 1044 by 788
// on the runner, so Notepad cannot take a 3440x1440 slot there. This window answers WM_GETMINMAXINFO
// with no cap, as every window on a real ultrawide is capped past its size, and stands in for the
// app under the fake ultrawide.
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
    print("stand: \(hex(WinWindows.id(hwnd))) pid \(GetCurrentProcessId())")
    pump(until: App.now + opts.seconds)
    if IsWindow(hwnd) {
        _ = DestroyWindow(hwnd)
    }
    return 0
}
