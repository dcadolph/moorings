import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

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
    // noDelta places without the border correction, the place probe's negative control.
    var noDelta = false
    // seconds is how long the moor probe runs its loop.
    var seconds = 10.0
    // paused writes a paused choices file, the moor probe's negative control.
    var paused = false
    // noFilter keeps every hooked event, the events probe's negative control.
    var noFilter = false
    // noApps builds the menu with no running apps, the menu probe's negative control.
    var noApps = false
    // pid names the process whose window the nudge probe moves.
    var pid: DWORD?
    // frame is where the nudge probe moves the window, or where the place probe places it.
    var frame: Frame?
    // screen replaces the monitor walk with one monitor of this size, so the runner acts as an
    // ultrawide.
    var screen: Size?
    // mode is the display mode the modes probe switches to.
    var mode: Size?
    // reset makes the modes probe restore the display mode kept in the registry.
    var reset = false
    // noHook runs the drag probe without the mouse hook, its negative control.
    var noHook = false
    // alt holds Alt through the drag probe's drop.
    var alt = false
    // activate leaves the footprint probe's window without its pass-through bits, its negative
    // control.
    var activate = false
    // app is the end of the image path of the app whose window the probes act on: Notepad, or the
    // stand probe's window under the fake ultrawide, which Windows would not size past the desktop.
    var app = "\\notepad.exe"
    // scenarios names the scenarios the scenarios probe runs, every one when empty.
    var scenarios: [String] = []
    // report is the folder the scenarios probe writes its report and pictures into.
    var report = "scenarios"
    // skew widens the strip the scenarios expect by this many pixels, their negative control.
    var skew = 0.0
    // url is the release record the update probe asks for in place of GitHub's.
    var url: URL?
    // current is the version the update probe checks as, in place of the build's.
    var current: String?
    // standIn is the lowercased path of a browser the scenarios open in place of the stand probe's
    // window, nil for the stand probe.
    var standIn: String?

    // init parses args, the command line without the program name.
    init(_ args: [String]) throws {
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--probe":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                probe = value
            case "--scenarios":
                probe = "scenarios"
                while let name = rest.first, !name.hasPrefix("--") {
                    scenarios.append(name)
                    rest = rest.dropFirst()
                }
            case "--report":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                report = value
            case "--skew":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n >= 0 else { throw ProbeError.badValue(flag, value) }
                skew = n
            case "--min-aspect":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n > 0 else { throw ProbeError.badValue(flag, value) }
                minAspect = n
            case "--url":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let u = URL(string: value), u.scheme != nil else { throw ProbeError.badValue(flag, value) }
                url = u
            case "--current":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard ReleaseVersion(value) != nil else { throw ProbeError.badValue(flag, value) }
                current = value
            case "--stand-in":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard FileManager.default.fileExists(atPath: value) else { throw ProbeError.badValue(flag, value) }
                standIn = value.lowercased()
            case "--no-delta":
                noDelta = true
            case "--paused":
                paused = true
            case "--no-filter":
                noFilter = true
            case "--no-apps":
                noApps = true
            case "--reset":
                reset = true
            case "--app":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                app = value.lowercased()
            case "--no-hook":
                noHook = true
            case "--alt":
                alt = true
            case "--activate":
                activate = true
            case "--screen", "--mode":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let size = Size(value) else { throw ProbeError.badValue(flag, value) }
                if flag == "--screen" {
                    screen = size
                } else {
                    mode = size
                }
            case "--seconds":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n > 0 else { throw ProbeError.badValue(flag, value) }
                seconds = n
            case "--pid":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = DWORD(value) else { throw ProbeError.badValue(flag, value) }
                pid = n
            case "--frame":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                let n = value.split(separator: ",").compactMap { Double($0) }
                guard n.count == 4, n[2] > 0, n[3] > 0 else { throw ProbeError.badValue(flag, value) }
                frame = Frame(x: n[0], y: n[1], w: n[2], h: n[3])
            default:
                throw ProbeError.unknownFlag(flag)
            }
        }
    }
}

// Size is a width and height in whole pixels, written WxH on the command line.
struct Size: Equatable {
    // w is the width.
    var w: Int
    // h is the height.
    var h: Int

    // init parses WxH, nil unless both are positive whole numbers.
    init?(_ text: String) {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
            return nil
        }
        self.w = w
        self.h = h
    }

    // init builds a size from a width and height.
    init(w: Int, h: Int) {
        self.w = w
        self.h = h
    }
}
