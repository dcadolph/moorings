import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeList prints one line per movable window, front-most first, and which one has focus.
func probeList(_ opts: ProbeOptions) -> Int32 {
    let (windows, focused) = WinWindows.scan(screens: .current(minAspect: opts.minAspect))
    for w in windows {
        print(
            "window \(hex(w.id)): \(w.bundle) frame \(pixels(w.frame))",
            "main \(w.isMain) fullscreen \(w.isFullScreen)")
    }
    print("focused: \(focused.map { hex($0.id) } ?? "none")")
    return 0
}
