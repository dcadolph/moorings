import Foundation
import WinSDK

import MooringsCore

// Report is the one text file a person sends back about a build: the version, the Windows build,
// each monitor, the choices file as written, how many windows each slot's app has open, and the end
// of the log. It names no window title and no app beyond the ones the choices file already holds.
enum Report {
    // logLines is how many of the log's last lines a report carries.
    static let logLines = 200

    // name returns the report's file name for date, in local time.
    static func name(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HHmm"
        return "Moorings report \(format.string(from: date)).txt"
    }

    // text builds the report for app at date.
    static func text(_ app: App, at date: Date) -> String {
        var lines = [String(name(date).dropLast(4)), "version: \(version)", "windows: \(windowsBuild())"]
        lines += monitors()
        let screens = Screens.current(minAspect: app.minAspect)
        lines.append(screens.hostLine)
        let open = WinWindows.scan(screens: screens).windows.map(\.bundle)
        let choices = app.engine.anchors.choices
        lines.append("slots:")
        for key in SlotKey.allCases {
            guard let bundle = choices.slots[key], !bundle.isEmpty else { continue }
            let count = open.filter { $0 == bundle }.count
            lines.append("slot \(key.title): \(Tray.appName(bundle)), \(count) open")
        }
        lines.append("choices: \(app.store.url.path)")
        if let file = try? String(contentsOf: app.store.url, encoding: .utf8) {
            lines.append(file.trimmingCharacters(in: .newlines))
        } else {
            lines.append("no choices file")
        }
        lines.append("log: \(LogFile.shared?.url.path ?? "none")")
        lines += LogFile.shared?.tail(logLines) ?? []
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // save writes the report for app at date into folder, a Windows path, notes where it went in
    // the log, and returns the file's path.
    static func save(_ app: App, in folder: String, at date: Date = Date()) throws -> String {
        let path = folder.hasSuffix("\\") ? folder + name(date) : folder + "\\" + name(date)
        try Data(text(app, at: date).utf8).write(to: URL(fileURLWithPath: path))
        app.log.note(.choices, "report saved to \(path)")
        return path
    }

    // desktop returns the current user's desktop folder as Explorer shows it, from the shell
    // folders key, which follows a desktop moved to OneDrive, nil when the key names none. RegGetValueW
    // expands the value's %USERPROFILE% when asked for a plain string.
    static func desktop() -> String? {
        let key = "Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders"
        var buffer = [WCHAR](repeating: 0, count: 32768)
        var bytes = DWORD(buffer.count * MemoryLayout<WCHAR>.size)
        guard
            RegGetValueW(LoginItem.currentUser, wide(key), wide("Desktop"), DWORD(RRF_RT_REG_SZ), nil, &buffer, &bytes)
                == ERROR_SUCCESS
        else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        return path.isEmpty ? nil : path
    }

    // windowsBuild returns the Windows version as major.minor.build from RtlGetVersion, which tells
    // the truth to a program without a compatibility manifest, or "unknown".
    static func windowsBuild() -> String {
        typealias GetVersion = @convention(c) (UnsafeMutablePointer<OSVERSIONINFOW>) -> LONG
        guard let ntdll = GetModuleHandleW(wide("ntdll.dll")), let proc = GetProcAddress(ntdll, "RtlGetVersion")
        else { return "unknown" }
        var info = OSVERSIONINFOW()
        info.dwOSVersionInfoSize = DWORD(MemoryLayout<OSVERSIONINFOW>.size)
        guard unsafeBitCast(proc, to: GetVersion.self)(&info) == 0 else { return "unknown" }
        return "\(info.dwMajorVersion).\(info.dwMinorVersion).\(info.dwBuildNumber)"
    }

    // monitors returns one line per attached monitor: its device name, its full and usable rects in
    // physical pixels, and its effective DPI, 0 when shcore gives none.
    static func monitors() -> [String] {
        let found = ReportMonitors()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumDisplayMonitors(
            nil, nil,
            { handle, _, _, context in
                let raw = UnsafeRawPointer(bitPattern: Int(context))!
                Unmanaged<ReportMonitors>.fromOpaque(raw).takeUnretainedValue().add(handle)
                return true
            }, context)
        return withExtendedLifetime(found) { found.lines }
    }
}

// ReportMonitors collects the report's monitor lines inside the EnumDisplayMonitors callback.
final class ReportMonitors {
    // devices is CCHDEVICENAME, the WCHARs of a device name after a MONITORINFO.
    static let devices = 32
    // lines holds one line per monitor, in enumeration order.
    var lines: [String] = []

    // add reads monitor through a MONITORINFOEXW laid out by hand, a MONITORINFO followed by the
    // device name, and appends its line.
    func add(_ monitor: HMONITOR?) {
        let head = MemoryLayout<MONITORINFO>.size
        let size = head + Self.devices * MemoryLayout<WCHAR>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let info = raw.bindMemory(to: MONITORINFO.self, capacity: 1)
        info.pointee.cbSize = DWORD(size)
        guard GetMonitorInfoW(monitor, info) else { return }
        let full = Frame(info.pointee.rcMonitor), usable = Frame(info.pointee.rcWork)
        let primary = info.pointee.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0
        let chars = (raw + head).bindMemory(to: WCHAR.self, capacity: Self.devices)
        let device = String(
            decoding: UnsafeBufferPointer(start: chars, count: Self.devices).prefix { $0 != 0 }, as: UTF16.self)
        lines.append(
            "monitor: \(device) full \(pixels(full)) usable \(pixels(usable)) primary \(primary) "
                + "dpi \(Monitor.dpi(monitor))")
    }
}
