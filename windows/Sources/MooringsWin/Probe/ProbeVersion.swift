import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeVersion prints the version and the DPI awareness the thread runs with.
func probeVersion(_: ProbeOptions) -> Int32 {
    print("version: \(version)")
    let v2 = AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), perMonitorAwareV2)
    print("dpi: \(v2 ? "per-monitor-v2" : "other")")
    return 0
}
