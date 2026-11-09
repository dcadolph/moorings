import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// probeLink prints how many tray windows exist and the channel, and with --pid the state of that
// process's window: whether it lives, its frame and whether it is in front. With --frame it first
// moves the window there and brings it forward, the known start for a link's action.
func probeLink(_ opts: ProbeOptions) -> Int32 {
    var trays = 0
    var after: HWND?
    while let next = FindWindowExW(nil, after, wide(Tray.className), nil) {
        trays += 1
        after = next
    }
    print("tray windows: \(trays)")
    let screens = Screens.current(minAspect: opts.minAspect)
    if let host = screens.hostFrame {
        let app = App(store: Store(), minAspect: opts.minAspect)
        print("channel: \(pixels(app.engine.anchors.channel(host)))")
    }
    guard let pid = opts.pid else { return 0 }
    let hwnd = WinWindows.topLevel().first {
        WinWindows.processID($0) == pid && WinWindows.describe($0, screens: screens) != nil
    }
    guard let hwnd else {
        print("window: gone")
        return 0
    }
    let windows = WinWindows()
    let id = WinWindows.id(hwnd)
    if let frame = opts.frame {
        windows.move(id, to: frame)
        bringForward(hwnd)
    }
    print("window: alive")
    print("frame: \(windows.frame(id).map(pixels) ?? "gone")")
    print("foreground: \(GetForegroundWindow() == hwnd ? "yes" : "no")")
    return 0
}
