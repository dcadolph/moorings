import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeMonitors prints one line per monitor and the index of the ultrawide among them.
func probeMonitors(_ opts: ProbeOptions) -> Int32 {
    let monitors = Monitor.all()
    for (i, m) in monitors.enumerated() {
        print(
            "monitor \(i): full \(pixels(m.full)) usable \(pixels(m.usable))",
            "primary \(m.primary)")
    }
    let index = Layout.ultrawide(monitors.map(\.full), minAspect: opts.minAspect)
    print("ultrawide: \(index.map(String.init) ?? "none")")
    return monitors.isEmpty ? 1 : 0
}
