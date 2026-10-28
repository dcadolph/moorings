import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

extension WinScreens {
    // displaySetKey names the attached monitors by device name and rect, sorted, so a workspace tied
    // to a set of monitors comes back only on those monitors, even when two share a size.
    func displaySetKey(_ screens: Screens) -> String {
        WinScreens.deviceKey()
    }

    // deviceKey reads each monitor's szDevice and rcMonitor, or keys the fake monitor by its frame.
    static func deviceKey() -> String {
        if let fake = Monitor.fake {
            return "fake@\(pixels(fake.full))"
        }
        let found = KeyList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumDisplayMonitors(nil, nil, { handle, _, _, context in
            let raw = UnsafeRawPointer(bitPattern: Int(context))!
            let found = Unmanaged<KeyList>.fromOpaque(raw).takeUnretainedValue()
            if let key = WinScreens.key(handle) {
                found.keys.append(key)
            }
            return true
        }, context)
        return withExtendedLifetime(found) { found.keys.sorted().joined(separator: " ") }
    }

    // key reads one monitor as MONITORINFOEXW: the MONITORINFO head, then the 32-character device
    // name right after it.
    private static func key(_ handle: HMONITOR?) -> String? {
        let head = MemoryLayout<MONITORINFO>.size
        let size = head + 32 * MemoryLayout<WCHAR>.size
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let info = buffer.bindMemory(to: MONITORINFO.self, capacity: 1)
        info.pointee.cbSize = DWORD(size)
        guard GetMonitorInfoW(handle, info) else { return nil }
        let rect = Frame(info.pointee.rcMonitor)
        let chars = UnsafeBufferPointer(start: (buffer + head).bindMemory(to: WCHAR.self, capacity: 32), count: 32)
        let name = String(decoding: chars.prefix { $0 != 0 }, as: UTF16.self)
        return "\(name)@\(pixels(rect))"
    }
}

// KeyList collects monitor keys inside the EnumDisplayMonitors callback.
final class KeyList {
    // keys holds the keys found so far.
    var keys: [String] = []
}

extension WinWindows {
    // title returns the window's title, empty when it has none or is gone.
    static func title(_ id: WindowID) -> String {
        guard let hwnd = hwnd(id) else { return "" }
        let n = GetWindowTextLengthW(hwnd)
        guard n > 0 else { return "" }
        var buffer = [WCHAR](repeating: 0, count: Int(n) + 1)
        let got = GetWindowTextW(hwnd, &buffer, n + 1)
        return String(decoding: buffer.prefix(Int(got)), as: UTF16.self)
    }

    // open starts the app a workspace saved, an exe path or a packaged app's user model id, with
    // target as its argument when one is given, without taking the foreground.
    static func open(_ bundle: String, target: String?) {
        let path = bundle.contains("!") ? "shell:AppsFolder\\" + bundle : bundle
        let args = target.map(wide)
        _ = path.withCString(encodedAs: UTF16.self) { file in
            if var args {
                return ShellExecuteW(nil, wide("open"), file, &args, nil, SW_SHOWNOACTIVATE)
            }
            return ShellExecuteW(nil, wide("open"), file, nil, nil, SW_SHOWNOACTIVATE)
        }
    }
}
