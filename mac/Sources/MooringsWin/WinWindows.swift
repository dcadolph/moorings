import WinSDK

import MooringsCore

extension Screens {
    // current reads the attached monitors. Only probes change minAspect.
    static func current(minAspect: Double = Layout.minAspect) -> Screens {
        let monitors = Monitor.all()
        let full = monitors.map(\.full)
        return Screens(full: full, usable: monitors.map(\.usable),
                       ultrawide: Layout.ultrawide(full, minAspect: minAspect))
    }
}

// Insets is how far a window's rect reaches past its visible frame on each edge, the invisible
// resize border Windows 10 and 11 draw outside the frame.
struct Insets: Equatable {
    // left is the border width on the left edge.
    var left = 0.0
    // top is the border height on the top edge.
    var top = 0.0
    // right is the border width on the right edge.
    var right = 0.0
    // bottom is the border height on the bottom edge.
    var bottom = 0.0
}

// WinWindows reads and moves other apps' top-level windows through Win32.
final class WinWindows {
    // frameHost is the image that hosts every packaged app's frame window.
    static let frameHost = "applicationframehost.exe"
    // coreWindowClass is the class of a packaged app's content window inside its frame.
    static let coreWindowClass = "Windows.UI.Core.CoreWindow"
    // accessDenied is ERROR_ACCESS_DENIED, which SetWindowPos returns for an elevated window.
    static let accessDenied: DWORD = 5

    // deltas caches each window's insets from its last placement.
    private(set) var deltas: [WindowID: Insets] = [:]
    // elevated holds windows that refused a move with access denied this session.
    private(set) var elevated: Set<WindowID> = []
    // corrects is false only in the probe's negative control, which places without the insets.
    var corrects = true

    // move places the window's visible frame at frame, restoring it first when it is maximized.
    func move(_ id: WindowID, to frame: Frame) {
        guard let hwnd = Self.hwnd(id) else { return }
        if IsZoomed(hwnd) {
            _ = ShowWindow(hwnd, SW_RESTORE)
        }
        guard corrects else {
            place(hwnd, id, frame, Insets())
            return
        }
        let cached = deltas[id] ?? Self.insets(hwnd) ?? Insets()
        guard place(hwnd, id, frame, cached) else { return }
        guard let now = Self.insets(hwnd) else { return }
        deltas[id] = now
        if now != cached {
            place(hwnd, id, frame, now)
        }
    }

    // position moves the window's visible frame to x, y and keeps its size.
    func position(_ id: WindowID, x: Double, y: Double) {
        guard let f = frame(id) else { return }
        move(id, to: Frame(x: x, y: y, w: f.w, h: f.h))
    }

    // resize sizes the window's visible frame to w by h and keeps its origin.
    func resize(_ id: WindowID, w: Double, h: Double) {
        guard let f = frame(id) else { return }
        move(id, to: Frame(x: f.x, y: f.y, w: w, h: h))
    }

    // frame returns the window's visible frame, nil when it is gone.
    func frame(_ id: WindowID) -> Frame? {
        Self.hwnd(id).flatMap(Self.bounds)
    }

    // place sets hwnd's rect so its visible frame lands on frame given its insets, and reports
    // whether Windows took it. Access denied marks the window elevated.
    @discardableResult
    private func place(_ hwnd: HWND, _ id: WindowID, _ frame: Frame, _ d: Insets) -> Bool {
        let x = Int32((frame.x - d.left).rounded()), y = Int32((frame.y - d.top).rounded())
        let w = Int32((frame.w + d.left + d.right).rounded())
        let h = Int32((frame.h + d.top + d.bottom).rounded())
        if SetWindowPos(hwnd, nil, x, y, w, h, UINT(SWP_NOZORDER | SWP_NOACTIVATE)) {
            return true
        }
        if GetLastError() == Self.accessDenied {
            elevated.insert(id)
        }
        return false
    }

    // hwnd returns the handle behind id.
    static func hwnd(_ id: WindowID) -> HWND? {
        HWND(bitPattern: UInt(id))
    }

    // insets returns how far hwnd's rect reaches past its visible frame, nil when either is
    // unknown.
    static func insets(_ hwnd: HWND) -> Insets? {
        var r = RECT()
        guard GetWindowRect(hwnd, &r), let f = bounds(hwnd) else { return nil }
        let outer = Frame(r)
        let right = outer.x + outer.w - (f.x + f.w), bottom = outer.y + outer.h - (f.y + f.h)
        return Insets(left: f.x - outer.x, top: f.y - outer.y, right: right, bottom: bottom)
    }

    // scan returns the movable windows front-most first, and the foreground window among them.
    static func scan(screens: Screens) -> (windows: [WindowInfo], focused: WindowInfo?) {
        var windows: [WindowInfo] = []
        var mains: Set<String> = []
        for hwnd in topLevel() {
            guard var info = describe(hwnd, screens: screens) else { continue }
            info.isMain = mains.insert(info.bundle).inserted
            windows.append(info)
        }
        let focused = GetForegroundWindow().flatMap { fg in windows.first { $0.id == id(fg) } }
        return (windows, focused)
    }

    // id returns the window id of hwnd.
    static func id(_ hwnd: HWND) -> WindowID {
        WindowID(UInt(bitPattern: hwnd))
    }

    // describe returns what a pass needs to know about hwnd, nil when it is not a movable window.
    static func describe(_ hwnd: HWND, screens: Screens) -> WindowInfo? {
        guard IsWindowVisible(hwnd), !IsIconic(hwnd), GetWindow(hwnd, UINT(GW_OWNER)) == nil,
              !cloaked(hwnd), let frame = bounds(hwnd) else { return nil }
        let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
        if exStyle & LONG_PTR(WS_EX_TOOLWINDOW) != 0 {
            return nil
        }
        let style = GetWindowLongPtrW(hwnd, GWL_STYLE)
        let caption = style & LONG_PTR(WS_CAPTION) == LONG_PTR(WS_CAPTION)
        let screen = screens.index(frame)
        let fills = screen.map { screens.full[$0] == frame } ?? false
        guard caption || fills, let bundle = bundle(hwnd) else { return nil }
        return WindowInfo(id: id(hwnd), bundle: bundle, frame: frame,
                          onUltrawide: screen != nil && screen == screens.ultrawide, isMain: false,
                          isFullScreen: fills && !caption)
    }

    // topLevel returns every top-level window in z order, front-most first.
    static func topLevel() -> [HWND] {
        let found = HandleList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumWindows({ hwnd, context in
            let raw = UnsafeRawPointer(bitPattern: Int(context))!
            if let hwnd {
                Unmanaged<HandleList>.fromOpaque(raw).takeUnretainedValue().handles.append(hwnd)
            }
            return true
        }, context)
        return withExtendedLifetime(found) { found.handles }
    }

    // children returns every child window of parent.
    static func children(_ parent: HWND) -> [HWND] {
        let found = HandleList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumChildWindows(parent, { hwnd, context in
            let raw = UnsafeRawPointer(bitPattern: Int(context))!
            if let hwnd {
                Unmanaged<HandleList>.fromOpaque(raw).takeUnretainedValue().handles.append(hwnd)
            }
            return true
        }, context)
        return withExtendedLifetime(found) { found.handles }
    }

    // cloaked reports whether DWM hides hwnd, as it does windows on other virtual desktops and
    // suspended packaged apps.
    static func cloaked(_ hwnd: HWND) -> Bool {
        var value: DWORD = 0
        let size = DWORD(MemoryLayout<DWORD>.size)
        let attribute = DWORD(DWMWA_CLOAKED.rawValue)
        return DwmGetWindowAttribute(hwnd, attribute, &value, size) >= 0 && value != 0
    }

    // bounds returns hwnd's visible frame without the invisible resize border, nil when DWM has
    // none or it is empty.
    static func bounds(_ hwnd: HWND) -> Frame? {
        var r = RECT()
        let size = DWORD(MemoryLayout<RECT>.size)
        let attribute = DWORD(DWMWA_EXTENDED_FRAME_BOUNDS.rawValue)
        guard DwmGetWindowAttribute(hwnd, attribute, &r, size) >= 0,
              r.right > r.left, r.bottom > r.top else { return nil }
        return Frame(r)
    }

    // bundle returns the identity a slot stores for hwnd's app: the packaged app's user model id
    // when hwnd is a frame host window, else the lowercased image path.
    static func bundle(_ hwnd: HWND) -> String? {
        let pid = processID(hwnd)
        guard let image = image(pid) else { return nil }
        guard image.hasSuffix("\\" + frameHost) else { return image }
        for child in children(hwnd) where className(child) == coreWindowClass {
            let childPID = processID(child)
            if childPID != pid, let id = aumid(childPID) ?? self.image(childPID) {
                return id
            }
        }
        return image
    }

    // processID returns the id of the process that owns hwnd.
    static func processID(_ hwnd: HWND) -> DWORD {
        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(hwnd, &pid)
        return pid
    }

    // image returns the lowercased full path of pid's executable, nil when it cannot be read.
    static func image(_ pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else {
            return nil
        }
        defer { _ = CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: 32768)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size) else { return nil }
        return String(decoding: buffer[..<Int(size)], as: UTF16.self).lowercased()
    }

    // aumid returns pid's application user model id, nil when it is not a packaged app.
    static func aumid(_ pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else {
            return nil
        }
        defer { _ = CloseHandle(process) }
        var length: UINT32 = 0
        _ = GetApplicationUserModelId(process, &length, nil)
        guard length > 1 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(length))
        guard GetApplicationUserModelId(process, &length, &buffer) == 0 else { return nil }
        return String(decoding: buffer[..<(Int(length) - 1)], as: UTF16.self)
    }

    // className returns hwnd's window class name.
    static func className(_ hwnd: HWND) -> String {
        var buffer = [WCHAR](repeating: 0, count: 256)
        let n = GetClassNameW(hwnd, &buffer, Int32(buffer.count))
        return String(decoding: buffer[..<Int(max(n, 0))], as: UTF16.self)
    }
}

// HandleList collects window handles inside an enumeration callback.
final class HandleList {
    // handles holds the handles found so far.
    var handles: [HWND] = []
}
