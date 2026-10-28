import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeNudge moves the front window of a process to a frame, the way an owner or an app would.
func probeNudge(_ opts: ProbeOptions) -> Int32 {
    guard let pid = opts.pid, let frame = opts.frame else {
        print("nudge: needs --pid and --frame")
        return 2
    }
    let screens = Screens.current(minAspect: opts.minAspect)
    let hwnd = WinWindows.topLevel().first {
        WinWindows.processID($0) == pid && WinWindows.describe($0, screens: screens) != nil
    }
    guard let hwnd else {
        print("nudge: no window for pid \(pid)")
        return 1
    }
    let id = WinWindows.id(hwnd)
    WinWindows().move(id, to: frame)
    print("nudged \(hex(id)) at \(stamp(App.now)) to \(pixels(frame))")
    return 0
}
