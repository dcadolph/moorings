import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// Command is what choosing a tray menu item does.
enum Command: Equatable {
    case slot(SlotKey, String)
    case widths(Widths)
    case action(String)
    case organize(String)
    case tidy(Int)
    case undoTidy
    case pause
    case atLogin
    case about
    case quit
}

// MenuItem is one tray menu entry: a separator when title is empty, a folder when submenu is
// nonempty, else a command.
struct MenuItem: Equatable {
    // title is the entry's label.
    var title: String
    // checked shows a check mark beside the entry.
    var checked = false
    // enabled is false for an entry shown but not chosen.
    var enabled = true
    // submenu holds a folder's entries.
    var submenu: [MenuItem] = []
    // command runs when the entry is chosen, nil for a folder, separator or label.
    var command: Command?

    // separator is the line between groups.
    static let separator = MenuItem(title: "")
}

// Tray shows the notification area icon and opens the menu on a click. Windows talks to it through
// a hidden window whose messages the App loop dispatches.
final class Tray {
    // app runs the passes the menu changes.
    let app: App
    // window receives the icon's clicks and the menu's commands.
    private(set) var window: HWND?
    // icon is the image the notification area shows.
    private var icon: HICON?
    // commands maps each open menu's item ids, from 1, to what they do.
    private var commands: [Command] = []
    // front is the window that was in front when the menu opened, which an organize command acts
    // from since the menu takes the focus.
    private var front: WindowID?

    // callback is the message the icon sends on a click, WM_APP + 1.
    static let callback = UINT(WM_APP + 1)
    // iconID names the one icon this process adds.
    static let iconID = UINT(1)
    // className is the hidden window's class.
    static let className = "MooringsTray"

    // init builds a tray for app. Call show to add the icon.
    init(app: App) {
        self.app = app
    }

    // current is the shown tray, which the window procedure reaches since it cannot capture.
    nonisolated(unsafe) static var current: Tray?
    // taskbarCreated is the message Explorer broadcasts when it restarts and every icon must be
    // added again.
    static let taskbarCreated = RegisterWindowMessageW(wide("TaskbarCreated"))

    // menu builds the tray menu from the choices, the bundles of the running apps, and whether
    // Moorings starts at login. It is pure so the menu probe can print it.
    static func menu(choices: Choices, running: [String], atLogin: Bool) -> [MenuItem] {
        let apps = Array(Set(running)).sorted { appName($0).lowercased() < appName($1).lowercased() }
        var slots: [MenuItem] = []
        for key in SlotKey.allCases {
            let current = choices.slots[key] ?? ""
            var items = [MenuItem(title: "Clear", checked: current.isEmpty, command: .slot(key, ""))]
            if !current.isEmpty && !apps.contains(current) {
                items.append(MenuItem(title: appName(current), checked: true, enabled: false))
            }
            for bundle in apps {
                items.append(MenuItem(title: appName(bundle), checked: bundle == current,
                                      command: .slot(key, bundle)))
            }
            let holder = current.isEmpty ? "empty" : appName(current)
            slots.append(MenuItem(title: "\(key.title): \(holder)", submenu: items))
        }
        let w = Layout.widths(saved: choices.widths, config: nil).0
        let pair = { (p: Widths) in
            MenuItem(title: String(format: "Left %.0f%%, right %.0f%%", p.left, p.right),
                     checked: p == w, command: .widths(p))
        }
        var widths = Layout.presets.map(pair)
        let owned = choices.widthPresets.filter { !Layout.presets.contains($0) }
        if !owned.isEmpty {
            widths.append(.separator)
            widths += owned.map(pair)
        }
        var organize = Tile.names.map { MenuItem(title: Keymaps.label($0), enabled: !choices.paused, command: .organize($0)) }
        organize.append(.separator)
        organize += Organizer.tidyCounts.map {
            MenuItem(title: "Tidy channel: \($0) front windows", enabled: !choices.paused, command: .tidy($0))
        }
        organize.append(MenuItem(title: "Undo tidy", enabled: !choices.paused, command: .undoTidy))
        let sizes = Bindings(choices).sizes.map {
            MenuItem(title: Keymaps.label($0.name), enabled: !choices.paused, command: .action($0.name))
        }
        return [
            MenuItem(title: "Slots", submenu: slots),
            MenuItem(title: "Widths", submenu: widths),
            MenuItem(title: "Organize", submenu: organize),
        ] + (sizes.isEmpty ? [] : [MenuItem(title: "Custom sizes", submenu: sizes)]) + [
            .separator,
            MenuItem(title: "Pause", checked: choices.paused, command: .pause),
            MenuItem(title: "Launch at login", checked: atLogin, command: .atLogin),
            .separator,
            MenuItem(title: "About Moorings", command: .about),
            MenuItem(title: "Quit Moorings", command: .quit),
        ]
    }

    // appName returns the name the menu shows for a bundle: the executable's file name for a path,
    // or the package name for a packaged app's user model id.
    static func appName(_ bundle: String) -> String {
        if bundle.contains("!") {
            let family = bundle.split(separator: "!").first.map(String.init) ?? bundle
            return family.split(separator: "_").first.map(String.init) ?? family
        }
        return bundle.split(separator: "\\").last.map(String.init) ?? bundle
    }

    // show creates the hidden window and adds the icon, and reports whether the icon was added.
    @discardableResult
    func show() -> Bool {
        guard window == nil else { return true }
        Tray.current = self
        let instance = GetModuleHandleW(nil)
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.hInstance = instance
        wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
            if let hwnd, let tray = Tray.current, let result = tray.handle(hwnd, msg, wParam, lParam) {
                return result
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
        let name = wide(Tray.className)
        name.withUnsafeBufferPointer { buffer in
            wc.lpszClassName = buffer.baseAddress
            _ = RegisterClassExW(&wc)
        }
        window = CreateWindowExW(0, name, wide("Moorings"), 0, 0, 0, 0, 0, nil, nil, instance, nil)
        icon = Tray.loadIcon()
        return add()
    }

    // hide removes the icon and the hidden window.
    func hide() {
        guard let window else { return }
        var data = Self.notifyData(window)
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
        _ = DestroyWindow(window)
        if let icon {
            _ = DestroyIcon(icon)
        }
        self.window = nil
        icon = nil
        Tray.current = nil
    }

    // iconGone reports whether the notification area no longer holds the icon window added, which
    // the quit probe asks after hide.
    static func iconGone(_ window: HWND) -> Bool {
        var data = notifyData(window)
        return !Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
    }

    // add puts the icon in the notification area and reports whether Windows took it.
    @discardableResult
    private func add() -> Bool {
        guard let window else { return false }
        var data = Self.notifyData(window)
        data.uFlags = UINT(NIF_MESSAGE | NIF_ICON | NIF_TIP)
        data.uCallbackMessage = Tray.callback
        data.hIcon = icon
        let tip = wide("Moorings")
        withUnsafeMutableBytes(of: &data.szTip) { raw in
            tip.prefix(raw.count / 2 - 1).withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        guard Shell_NotifyIconW(DWORD(NIM_ADD), &data) else {
            FileHandle.standardError.write(Data("tray: icon not added: error \(GetLastError())\n".utf8))
            return false
        }
        return true
    }

    // notifyData returns the record that names this process's icon.
    private static func notifyData(_ window: HWND) -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = Tray.iconID
        return data
    }

    // handle answers the hidden window's messages, nil for the ones the default procedure takes.
    private func handle(_ hwnd: HWND, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch msg {
        case Tray.callback:
            let event = UINT(lParam & 0xFFFF)
            if event == UINT(WM_LBUTTONUP) || event == UINT(WM_RBUTTONUP) {
                open(hwnd)
            }
            return 0
        case UINT(WM_COMMAND):
            let id = Int(wParam & 0xFFFF)
            if id >= 1 && id <= commands.count {
                perform(commands[id - 1])
            }
            return 0
        case Tray.taskbarCreated where Tray.taskbarCreated != 0:
            add()
            return 0
        default:
            return nil
        }
    }

    // open shows the menu at the cursor. The window comes to the front first so the menu closes
    // when the owner clicks elsewhere.
    private func open(_ hwnd: HWND) {
        let scan = WinWindows.scan(screens: .current(minAspect: app.minAspect)).windows
        let items = Tray.menu(choices: app.anchors.choices, running: scan.map(\.bundle), atLogin: LoginItem.enabled)
        commands = []
        let foreground = GetForegroundWindow()
        let id = foreground.map { WinWindows.id($0) }
        front = scan.contains { $0.id == id } ? id : scan.first?.id
        guard let menu = build(items) else { return }
        defer { _ = DestroyMenu(menu) }
        var cursor = POINT()
        _ = GetCursorPos(&cursor)
        _ = SetForegroundWindow(hwnd)
        _ = TrackPopupMenuEx(menu, UINT(TPM_RIGHTBUTTON), cursor.x, cursor.y, hwnd, nil)
        _ = PostMessageW(hwnd, UINT(WM_NULL), 0, 0)
        if let front, let back = WinWindows.hwnd(front) {
            _ = SetForegroundWindow(back)
        }
    }

    // openAtCursor opens the menu under the pointer, as the show-menu action does, and gives the
    // foreground back to the window in front once it closes. It reports whether the menu opened.
    func openAtCursor() -> Bool {
        guard let window else { return false }
        open(window)
        return true
    }

    // build turns items into a popup menu, numbering each command in commands.
    private func build(_ items: [MenuItem]) -> HMENU? {
        guard let menu = CreatePopupMenu() else { return nil }
        for item in items {
            var flags = UINT(MF_STRING)
            var id = UINT_PTR(0)
            if item.title.isEmpty {
                flags = UINT(MF_SEPARATOR)
            } else if !item.submenu.isEmpty, let sub = build(item.submenu) {
                flags |= UINT(MF_POPUP)
                id = UINT_PTR(UInt(bitPattern: sub))
            } else if let command = item.command {
                commands.append(command)
                id = UINT_PTR(commands.count)
            }
            if item.checked {
                flags |= UINT(MF_CHECKED)
            }
            if !item.enabled {
                flags |= UINT(MF_GRAYED)
            }
            if item.title.isEmpty {
                _ = AppendMenuW(menu, flags, id, nil)
            } else {
                _ = AppendMenuW(menu, flags, id, wide(item.title))
            }
        }
        return menu
    }

    // perform carries out a chosen command, saves the choices, and runs a pass.
    func perform(_ command: Command) {
        let anchors = app.anchors
        switch command {
        case .slot(let key, let bundle):
            anchors.lock(key, bundle, now: App.now)
        case .widths(let w):
            anchors.setWidths(w)
        case .action(let name):
            app.actions.run(name, window: front)
            return
        case .organize(let name):
            app.organizer.run(name, window: front)
            return
        case .tidy(let n):
            app.organizer.tidy(n)
            return
        case .undoTidy:
            app.organizer.undo()
            return
        case .pause:
            anchors.choices.paused.toggle()
        case .atLogin:
            LoginItem.enabled.toggle()
            return
        case .about:
            let text = "Moorings \(version)\nHolds apps in the side strips of an ultrawide."
            _ = MessageBoxW(window, wide(text), wide("About Moorings"), UINT(MB_OK | MB_ICONINFORMATION))
            return
        case .quit:
            PostQuitMessage(0)
            return
        }
        app.save()
        app.wake()
    }

    // loadIcon builds the small icon from the embedded .ico, picking the smallest image at least
    // the system's small icon size.
    static func loadIcon() -> HICON? {
        let ico = PackageResources.moorings_ico
        guard ico.count >= 6 else { return nil }
        let size = Int(GetSystemMetrics(SM_CXSMICON))
        let count = Int(ico[4]) | Int(ico[5]) << 8
        var images: [(side: Int, length: Int, offset: Int)] = []
        for i in 0..<count where 6 + 16 * (i + 1) <= ico.count {
            let at = 6 + 16 * i
            let side = ico[at] == 0 ? 256 : Int(ico[at])
            let length = le32(ico, at + 8), offset = le32(ico, at + 12)
            if offset + length <= ico.count {
                images.append((side, length, offset))
            }
        }
        images.sort { $0.side < $1.side }
        let best = images.first { $0.side >= size } ?? images.last
        guard let best else { return nil }
        var bytes = Array(ico[best.offset..<(best.offset + best.length)])
        return CreateIconFromResourceEx(&bytes, DWORD(best.length), true, 0x0003_0000,
                                        Int32(size), Int32(size), UINT(LR_DEFAULTCOLOR))
    }

    // le32 reads a little-endian 32-bit value from bytes at index.
    private static func le32(_ bytes: [UInt8], _ index: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(bytes[index + $1]) << (8 * $1) }
    }
}

// LoginItem starts Moorings at sign-in through the current user's Run key.
enum LoginItem {
    // runKey is the registry key Windows reads at sign-in.
    static let runKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    // valueName names Moorings' entry under the key.
    static let valueName = "Moorings"
    // currentUser is HKEY_CURRENT_USER, a cast macro Swift does not import.
    static var currentUser: HKEY? { HKEY(bitPattern: UInt(0xFFFF_FFFF_8000_0001)) }

    // enabled reports or sets whether the Run key holds an entry for Moorings.
    static var enabled: Bool {
        get {
            RegGetValueW(currentUser, wide(runKey), wide(valueName), DWORD(RRF_RT_REG_SZ), nil, nil, nil)
                == ERROR_SUCCESS
        }
        set {
            let status: LSTATUS
            if newValue {
                let command = wide("\"\(executable)\"")
                let bytes = DWORD(command.count * MemoryLayout<WCHAR>.size)
                status = RegSetKeyValueW(currentUser, wide(runKey), wide(valueName), DWORD(REG_SZ), command, bytes)
            } else {
                status = RegDeleteKeyValueW(currentUser, wide(runKey), wide(valueName))
            }
            if status != ERROR_SUCCESS {
                let line = "tray: launch at login not changed: error \(status)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
    }

    // executable is the full path of the running program.
    static var executable: String {
        var buffer = [WCHAR](repeating: 0, count: 32768)
        let n = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
        return String(decoding: buffer[..<Int(n)], as: UTF16.self)
    }
}

// wide returns s as a NUL-terminated UTF-16 string for the W functions.
func wide(_ s: String) -> [WCHAR] {
    Array(s.utf16) + [0]
}
