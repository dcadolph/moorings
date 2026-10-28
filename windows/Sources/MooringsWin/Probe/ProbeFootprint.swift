import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeFootprint brings the front Notepad forward, shows the footprint over it at the given frame,
// or inside Notepad, and prints its rect, its style bits and the foreground window after the show
// and after a click on the footprint's middle.
func probeFootprint(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("footprint: no window of \(opts.app)")
        return 1
    }
    _ = bringForward(hwnd)
    pump(until: App.now + 0.3)
    print("foreground before: \(foreground()) notepad \(hex(pad.id))")
    let f = opts.frame ?? Frame(x: pad.frame.x + 50, y: pad.frame.y + 50, w: 300, h: 200)
    let footprint = WinFootprint()
    footprint.activates = opts.activate
    footprint.show(f, style: FootprintStyle())
    pump(until: App.now + 0.5)
    guard let window = footprint.window else {
        print("footprint: no window: \(GetLastError())")
        return 1
    }
    var r = RECT()
    _ = GetWindowRect(window, &r)
    print("rect: \(pixels(Frame(r)))")
    let ex = DWORD(truncatingIfNeeded: GetWindowLongPtrW(window, GWL_EXSTYLE))
    let bit = { (b: DWORD) in ex & b == b }
    print(
        "exstyle: transparent \(bit(WinFootprint.transparent)) noactivate \(bit(WinFootprint.noActivate))",
        "layered \(bit(WinFootprint.layered)) topmost \(bit(WinFootprint.topmost))",
        "toolwindow \(bit(WinFootprint.toolWindow))")
    print("visible: \(IsWindowVisible(window))")
    print("foreground after show: \(foreground())")
    let mid = (x: Int32((f.x + f.w / 2).rounded()), y: Int32((f.y + f.h / 2).rounded()))
    sendMouse(mid.x, mid.y, 0)
    pump(until: App.now + 0.1)
    sendMouse(mid.x, mid.y, 0x0002)
    sendMouse(mid.x, mid.y, 0x0004)
    pump(until: App.now + 0.5)
    print("foreground after click: \(foreground()) footprint \(hex(WinWindows.id(window)))")
    footprint.hide()
    pump(until: App.now + 0.3)
    print("visible after hide: \(IsWindowVisible(window))")
    return 0
}
