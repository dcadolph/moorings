import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeBanner shows a banner and prints its rect, the scale, the screen it centers on, whether it
// took the foreground, and whether it closed itself after the fade.
func probeBanner(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let screen = screens.wide ?? screens.usable.first else {
        print("banner: no screen")
        return 1
    }
    let before = GetForegroundWindow()
    let banner = BannerWindow(minAspect: opts.minAspect)
    banner.show(
        "Moorings",
        "The banner probe shows this box, which fades after three seconds and never "
            + "takes the foreground.")
    guard let hwnd = banner.window else {
        print("banner: not shown")
        return 1
    }
    var r = RECT()
    _ = GetWindowRect(hwnd, &r)
    let exStyle = DWORD(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    print("banner: \(pixels(Frame(r))) scale \(banner.scale)")
    print("screen: \(pixels(screen))")
    print(
        "visible: \(IsWindowVisible(hwnd)) topmost: \(exStyle & 0x8 != 0)",
        "noactivate: \(exStyle & 0x0800_0000 != 0)")
    pump(until: App.now + 1)
    print("foreground is banner: \(GetForegroundWindow() == hwnd) kept: \(GetForegroundWindow() == before)")
    print("open at 1 s: \(IsWindow(hwnd))")
    pump(until: App.now + BannerWindow.seconds + BannerWindow.fadeSeconds + 1)
    print("closed: \(!IsWindow(hwnd))")
    return 0
}
