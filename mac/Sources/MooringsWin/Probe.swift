import Foundation
import WinSDK

import MooringsCore

// version is the build's version, shown by the version probe and, later, the tray's About item.
let version = "dev"

// perMonitorAwareV2 is DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, a cast macro Swift does not
// import.
var perMonitorAwareV2: DPI_AWARENESS_CONTEXT? { DPI_AWARENESS_CONTEXT(bitPattern: -4) }

// ProbeError is a bad probe command line.
enum ProbeError: Error, CustomStringConvertible {
    case missingValue(String)
    case badValue(String, String)
    case unknownFlag(String)

    // description says what was wrong with the command line.
    var description: String {
        switch self {
        case .missingValue(let flag): "\(flag) needs a value"
        case .badValue(let flag, let value): "\(flag) does not take \(value)"
        case .unknownFlag(let flag): "unknown flag \(flag)"
        }
    }
}

// ProbeOptions holds the probe command line.
struct ProbeOptions {
    // probe is the probe to run, or nil to run the app.
    var probe: String?
    // minAspect is the ratio a monitor needs to count as ultrawide. Only probes set it.
    var minAspect = Layout.minAspect

    // init parses args, the command line without the program name.
    init(_ args: [String]) throws {
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--probe":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                probe = value
            case "--min-aspect":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n > 0 else { throw ProbeError.badValue(flag, value) }
                minAspect = n
            default:
                throw ProbeError.unknownFlag(flag)
            }
        }
    }
}

// Probe runs one mechanism, prints lines the Windows workflow checks, and returns the exit code.
typealias Probe = @Sendable (ProbeOptions) -> Int32

// probes maps each probe name to its function.
let probes: [String: Probe] = [
    "version": probeVersion,
    "monitors": probeMonitors,
]

// probeVersion prints the version and the DPI awareness the thread runs with.
func probeVersion(_: ProbeOptions) -> Int32 {
    print("version: \(version)")
    let v2 = AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), perMonitorAwareV2)
    print("dpi: \(v2.boolValue ? "per-monitor-v2" : "other")")
    return 0
}

// probeMonitors prints one line per monitor and the index of the ultrawide among them.
func probeMonitors(_ opts: ProbeOptions) -> Int32 {
    let monitors = Monitor.all()
    for (i, m) in monitors.enumerated() {
        print("monitor \(i): full \(pixels(m.full)) usable \(pixels(m.usable))",
              "primary \(m.primary)")
    }
    let index = Layout.ultrawide(monitors.map(\.full), minAspect: opts.minAspect)
    print("ultrawide: \(index.map(String.init) ?? "none")")
    return monitors.isEmpty ? 1 : 0
}

// pixels formats f as whole x, y, w and h, the same in every locale.
func pixels(_ f: Frame) -> String {
    "\(Int(f.x)) \(Int(f.y)) \(Int(f.w)) \(Int(f.h))"
}

// Monitor is one display as Windows reports it, in top-left physical pixels.
struct Monitor {
    // full is rcMonitor, the whole display.
    var full: Frame
    // usable is rcWork, the display without the taskbar.
    var usable: Frame
    // primary is true for the display that holds the origin.
    var primary: Bool

    // all returns every monitor in EnumDisplayMonitors order.
    static func all() -> [Monitor] {
        let found = MonitorList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumDisplayMonitors(nil, nil, { handle, _, _, context in
            let raw = UnsafeRawPointer(bitPattern: Int(context))!
            let found = Unmanaged<MonitorList>.fromOpaque(raw).takeUnretainedValue()
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            if GetMonitorInfoW(handle, &info).boolValue {
                let primary = info.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0
                let full = frame(info.rcMonitor), usable = frame(info.rcWork)
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

// frame converts a Win32 RECT to a Frame.
func frame(_ r: RECT) -> Frame {
    Frame(x: Double(r.left), y: Double(r.top), w: Double(r.right - r.left),
          h: Double(r.bottom - r.top))
}
