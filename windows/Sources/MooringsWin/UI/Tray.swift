import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// Command is what choosing a tray menu item does.
enum Command: Equatable {
    case slot(SlotKey, String)
    case widths(Widths)
    case action(String)
    case tidy(Int)
    case undoTidy
    case saveWorkspace
    case recallWorkspace(String)
    case tieWorkspace(String)
    case openMissing(String)
    case deleteWorkspace(String)
    case pause
    case unstashAll
    case openSettings
    case reloadSettings
    case atLogin
    case saveReport
    case about
    case openRelease(URL)
    case quit

    // opensWindow reports whether the command shows a window of its own, which keeps the foreground
    // the menu took instead of handing it back.
    var opensWindow: Bool {
        switch self {
        case .about, .openSettings, .saveReport, .openRelease:
            return true
        default:
            return false
        }
    }
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
    // front is the window an organize command acts on: the focused window when the menu opened, else
    // the front-most one in the z order, since a click on the icon hands the foreground to the taskbar.
    private var front: WindowID?
    // update looks for a newer release, nil until watchUpdates and in a dev build.
    private(set) var update: WinUpdate?
    // updates runs the update tick on the message loop.
    private var updates: WinScheduler?
    // told is the tag of the release a banner already announced.
    private var told: String?
    // links holds the work the links asked for, run in order from the message queue.
    private var links: [() -> Void] = []

    // callback is the message the icon sends on a click, WM_APP + 1.
    static let callback = UINT(WM_APP + 1)
    // updated is the message an update check posts when it ends, WM_APP + 2.
    static let updated = UINT(WM_APP + 2)
    // link is the message that runs the next link's work from the queue, WM_APP + 3.
    static let link = UINT(WM_APP + 3)
    // again is the message a second plain launch posts before it exits, WM_APP + 4.
    static let again = UINT(WM_APP + 4)
    // pointer is the message the menu action posts to open the menu under the pointer, WM_APP + 5.
    static let pointer = UINT(WM_APP + 5)
    // updateTick is how often the tray asks whether an update check is due, in seconds.
    static let updateTick = 60.0
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

    // menu builds the tray menu from the choices, the bundles of the running apps, whether Moorings
    // starts at login, whether the host is an ultrawide, the only display with Widths to pick, the
    // newer release a check found, which comes first, whether a window is stashed, whether a tidy can
    // be undone, and the key of the displays attached now. It is pure so the menu and update probes
    // can print it.
    static func menu(
        choices: Choices, running: [String], atLogin: Bool, isUltrawide: Bool, update: ReleaseInfo? = nil,
        stashed: Bool = false, canUndo: Bool = false, displays: String = ""
    ) -> [MenuItem] {
        let apps = Array(Set(running)).sorted { appName($0).lowercased() < appName($1).lowercased() }
        var slots: [MenuItem] = []
        for key in SlotKey.allCases {
            let current = choices.slots[key] ?? ""
            var items = [MenuItem(title: "Clear", checked: current.isEmpty, command: .slot(key, ""))]
            if !current.isEmpty && !apps.contains(current) {
                items.append(MenuItem(title: appName(current), checked: true, enabled: false))
            }
            for bundle in apps {
                items.append(
                    MenuItem(
                        title: appName(bundle), checked: bundle == current,
                        command: .slot(key, bundle)))
            }
            let holder = current.isEmpty ? "empty" : appName(current)
            slots.append(MenuItem(title: "\(key.title): \(holder)", submenu: items))
        }
        let w = Layout.widths(saved: choices.widths, config: nil).0
        let pair = { (p: Widths) in
            MenuItem(
                title: String(format: "Left %.0f%%, right %.0f%%", p.left, p.right),
                checked: p == w, command: .widths(p))
        }
        var widths = Layout.presets.map(pair)
        let owned = choices.widthPresets.filter { !Layout.presets.contains($0) }
        if !owned.isEmpty {
            widths.append(.separator)
            widths += owned.map(pair)
        }
        let offer = update.map {
            [MenuItem(title: "Update available: \($0.tag)", command: .openRelease($0.page)), .separator]
        }
        var items: [MenuItem] = offer ?? []
        items.append(MenuItem(title: "Slots", submenu: slots))
        if isUltrawide {
            items.append(MenuItem(title: "Widths", submenu: widths))
        }
        items += organizeFolders(choices: choices, canUndo: canUndo)
        if let sizes = sizesFolder(choices: choices) {
            items.append(sizes)
        }
        items.append(workspacesFolder(choices: choices, displays: displays))
        items.append(.separator)
        if stashed {
            items.append(MenuItem(title: "Unstash all windows", command: .unstashAll))
        }
        return items + [
            MenuItem(title: "Pause", checked: choices.paused, command: .pause),
            MenuItem(title: "Open settings file", command: .openSettings),
            MenuItem(title: "Reload settings", command: .reloadSettings),
            MenuItem(title: "Launch at login", checked: atLogin, command: .atLogin),
            .separator,
            MenuItem(title: "Save a report", command: .saveReport),
            MenuItem(title: "About Moorings", command: .about),
            MenuItem(title: "Quit Moorings", command: .quit),
        ]
    }

    // organizeFolders builds the Organize and Channel folders the way the Mac groups them: the organize
    // actions, then the channel actions with Tidy for the front two or three windows, each ending in
    // Undo tidy. Hidden actions are left out, and every entry is off while paused.
    static func organizeFolders(choices: Choices, canUndo: Bool) -> [MenuItem] {
        let on = !choices.paused
        let entry = { (name: String) in MenuItem(title: Keymaps.label(name), enabled: on, command: .action(name)) }
        let undo = MenuItem(title: "Undo tidy", enabled: on && canUndo, command: .undoTidy)
        var organize = choices.menu.visible(Tile.names.filter { !Tile.channelNames.contains($0) }).map(entry)
        organize += [.separator, undo]
        var channel = choices.menu.visible(Tile.channelNames).map(entry)
        channel.append(.separator)
        channel += Organizer.tidyCounts.map {
            MenuItem(title: "Tidy \($0) front windows", enabled: on, command: .tidy($0))
        }
        channel += [.separator, undo]
        return [MenuItem(title: "Organize", submenu: organize), MenuItem(title: "Channel", submenu: channel)]
    }

    // sizesFolder builds the Custom sizes folder from the valid custom sizes in menu order, each off
    // while paused, and nil when there are none.
    static func sizesFolder(choices: Choices) -> MenuItem? {
        let sizes = Bindings(choices).sizes.map {
            MenuItem(title: Keymaps.label($0.name), enabled: !choices.paused, command: .action($0.name))
        }
        return sizes.isEmpty ? nil : MenuItem(title: "Custom sizes", submenu: sizes)
    }

    // workspacesFolder builds the Workspaces folder: Save workspace, then a folder per saved workspace
    // in name order with Recall, Recall with these displays, checked when it is tied to displays, Open
    // apps that are not running, and Delete. Saving and recalling are off while paused.
    static func workspacesFolder(choices: Choices, displays: String) -> MenuItem {
        let on = !choices.paused
        var items = [MenuItem(title: "Save workspace", enabled: on, command: .saveWorkspace)]
        let names = choices.workspaces.keys.sorted()
        if !names.isEmpty {
            items.append(.separator)
        }
        for name in names {
            guard let ws = choices.workspaces[name] else { continue }
            let tied = !displays.isEmpty && ws.setup == displays
            let opens = opensMissing(ws)
            let entries = [
                MenuItem(title: "Recall", enabled: on, command: .recallWorkspace(name)),
                MenuItem(title: "Recall with these displays", checked: tied, command: .tieWorkspace(name)),
                MenuItem(title: "Open apps that are not running", checked: opens, command: .openMissing(name)),
                MenuItem(title: "Delete", command: .deleteWorkspace(name)),
            ]
            items.append(MenuItem(title: name, submenu: entries))
        }
        return MenuItem(title: "Workspaces", submenu: items)
    }

    // opensMissing reports whether a recall of ws opens the app of every saved window that has none
    // running, as the Mac's setting reads it.
    static func opensMissing(_ ws: Workspace) -> Bool {
        !ws.windows.isEmpty && ws.windows.allSatisfy { $0.launchBundle != nil }
    }

    // freeWorkspaceName returns Workspace 1, or the first Workspace N no saved workspace holds.
    static func freeWorkspaceName(_ choices: Choices) -> String {
        (1...).lazy.map { "Workspace \($0)" }.first { choices.workspaces[$0] == nil } ?? "Workspace"
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
        app.menu.open = { [weak self] in
            guard let window = self?.window else { return false }
            return PostMessageW(window, Tray.pointer, 0, 0)
        }
        return add()
    }

    // watchUpdates starts the update tick: once a minute it starts a check when the choices allow
    // one and the core's schedule says it is due. A dev build never checks. A check that ends posts
    // updated to the hidden window, so its news reaches the menu and the banner on this thread.
    func watchUpdates() {
        guard update == nil, let window, let current = ReleaseVersion(version) else { return }
        let bits = UInt(bitPattern: window)
        update = WinUpdate(checker: UpdateChecker(client: URLSessionClient(), current: current, platform: .windows)) {
            result in
            if case .failure(let error) = result {
                FileHandle.standardError.write(Data("update: check failed: \(error)\n".utf8))
            }
            _ = PostMessageW(HWND(bitPattern: bits), Tray.updated, 0, 0)
        }
        updates = app.timers.make()
        tick()
    }

    // tick starts a check when one is due and schedules the next tick.
    private func tick() {
        if app.engine.anchors.choices.checkUpdates, let update, update.due() {
            update.start()
        }
        updates?.schedule(at: App.now + Self.updateTick) { [weak self] in self?.tick() }
    }

    // announce shows a banner for a newer release the first time a check names it.
    private func announce() {
        guard let found = update?.found, found.tag != told else { return }
        told = found.tag
        app.notify("Moorings \(found.tag) is out", "Choose Update available in the tray menu to open the release page.")
    }

    // hide removes the icon and the hidden window.
    func hide() {
        updates?.cancel()
        app.menu.open = nil
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
        case Tray.updated:
            announce()
            return 0
        case UINT(WM_COPYDATA):
            return receive(lParam)
        case Tray.link:
            if !links.isEmpty {
                links.removeFirst()()
            }
            return 0
        case Tray.again:
            app.notify("Moorings is already running", "Its icon is in the notification area.")
            return 0
        case Tray.pointer:
            open(hwnd)
            return 0
        case UINT(WM_ENDSESSION) where wParam != 0:
            app.engine.shutdown()
            return 0
        case UINT(WM_DISPLAYCHANGE):
            app.displaysChanged()
            return 0
        case UINT(WM_WININICHANGE) where wParam == WPARAM(SPI_SETWORKAREA):
            app.displaysChanged()
            return 0
        case Tray.taskbarCreated where Tray.taskbarCreated != 0:
            add()
            return 0
        default:
            return nil
        }
    }

    // receive reads a link's action name from a WM_COPYDATA message and returns the answer for its
    // sender, zero for a message that is not one.
    private func receive(_ lParam: LPARAM) -> LRESULT {
        guard let data = UnsafePointer<COPYDATASTRUCT>(bitPattern: Int(lParam))?.pointee, data.dwData == Links.tag,
            Int(data.cbData) <= Links.limit, let bytes = data.lpData
        else { return 0 }
        return answer(String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(data.cbData)), as: UTF8.self))
    }

    // answer decides what a link asking for name gets and queues the work. A sent message can arrive
    // while a pass waits on another process's window, so nothing here may enter the engine: the
    // verdict only reads, and the action runs later from the queue, in order.
    func answer(_ name: String) -> LRESULT {
        let verdict = app.engine.actions.linkVerdict(name)
        queue { [unowned self] in
            switch verdict {
            case .run:
                app.engine.actions.run(name)
            case .unknown:
                app.log.note(.actions, "a moorings link asked for unknown action \(name)")
            case .refused(let refused):
                let why = "Closing actions run only from shortcuts and the menu."
                app.log.note(.actions, "a moorings link asked for \(refused): \(why)")
                app.notify("Moorings", "A link asked to \(refused). \(why)")
            }
        }
        return Links.answer(verdict)
    }

    // queue runs work once the message queue reaches it.
    private func queue(_ work: @escaping () -> Void) {
        links.append(work)
        _ = PostMessageW(window, Tray.link, 0, 0)
    }

    // open shows the menu at the cursor. The hidden window takes the foreground first so the menu
    // closes when the owner clicks elsewhere. Once it closes, the foreground goes back to the window
    // in front, unless the chosen command shows a window of its own, and then the command runs.
    private func open(_ hwnd: HWND) {
        let screens = Screens.current(minAspect: app.minAspect)
        let scan = WinWindows.scan(screens: screens)
        let running = scan.windows.map(\.bundle)
        front = (scan.focused ?? scan.windows.first)?.id
        let items = Tray.menu(
            choices: app.engine.anchors.choices, running: running, atLogin: LoginItem.enabled,
            isUltrawide: screens.isUltrawide, update: update?.found, stashed: !app.engine.stasher.entries.isEmpty,
            canUndo: app.engine.anchors.canUndo, displays: app.screens.displaySetKey(screens))
        commands = []
        guard let menu = build(items) else { return }
        defer { _ = DestroyMenu(menu) }
        var cursor = POINT()
        _ = GetCursorPos(&cursor)
        _ = SetForegroundWindow(hwnd)
        _ = TrackPopupMenuEx(menu, UINT(TPM_RIGHTBUTTON), cursor.x, cursor.y, hwnd, nil)
        _ = PostMessageW(hwnd, UINT(WM_NULL), 0, 0)
        var msg = MSG()
        let picked = PeekMessageW(&msg, hwnd, UINT(WM_COMMAND), UINT(WM_COMMAND), UINT(PM_REMOVE))
        let id = picked ? Int(msg.wParam & 0xFFFF) : 0
        let command = id >= 1 && id <= commands.count ? commands[id - 1] : nil
        if command?.opensWindow != true, let front, let back = WinWindows.hwnd(front) {
            _ = SetForegroundWindow(back)
        }
        if let command {
            perform(command)
        }
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
        let anchors = app.engine.anchors
        switch command {
        case .slot(let key, let bundle):
            anchors.lock(key, bundle, now: App.now)
        case .widths(let w):
            anchors.setWidths(w)
        case .action(let name):
            app.engine.actions.run(name, window: front)
            return
        case .tidy(let n):
            if let front {
                app.windows.raise(front)
            }
            app.engine.organizer.tidy(n)
            return
        case .undoTidy:
            app.engine.organizer.undo()
            return
        case .saveWorkspace:
            app.engine.workspaces.saveWorkspace(Tray.freeWorkspaceName(anchors.choices))
            return
        case .recallWorkspace(let name):
            app.engine.workspaces.recall(name)
            return
        case .tieWorkspace(let name):
            app.engine.workspaces.tie(name)
            return
        case .openMissing(let name):
            guard var ws = anchors.choices.workspaces[name] else { return }
            let open = !Tray.opensMissing(ws)
            for i in ws.windows.indices {
                ws.windows[i].launchBundle = open ? ws.windows[i].bundle : nil
            }
            anchors.choices.workspaces[name] = ws
        case .deleteWorkspace(let name):
            app.engine.workspaces.delete(name)
            return
        case .pause:
            anchors.choices.paused.toggle()
        case .unstashAll:
            app.engine.stasher.unstashAll()
            return
        case .openSettings:
            openSettings()
            return
        case .reloadSettings:
            app.engine.reload()
            return
        case .atLogin:
            LoginItem.enabled.toggle()
            return
        case .saveReport:
            saveReport()
            return
        case .about:
            let text = "Moorings \(version)\nHolds apps in the side strips of your widest display."
            _ = MessageBoxW(window, wide(text), wide("About Moorings"), UINT(MB_OK | MB_ICONINFORMATION))
            return
        case .openRelease(let page):
            let result = ShellExecuteW(window, wide("open"), wide(page.absoluteString), nil, nil, SW_SHOWNORMAL)
            if Int(bitPattern: result) <= 32 {
                FileHandle.standardError.write(Data("tray: release page not opened: \(Int(bitPattern: result))\n".utf8))
            }
            return
        case .quit:
            app.engine.shutdown()
            PostQuitMessage(0)
            return
        }
        app.engine.save()
    }

    // saveReport writes a report to the desktop, or beside the program when Windows names no
    // desktop, and opens its folder in Explorer with the file selected.
    private func saveReport() {
        let exe = LoginItem.executable
        let folder = Report.desktop() ?? String(exe[..<(exe.lastIndex(of: "\\") ?? exe.endIndex)])
        do {
            let file = try Report.save(app, in: folder)
            let result = ShellExecuteW(
                window, wide("open"), wide("explorer.exe"), wide("/select,\"\(file)\""), nil, SW_SHOWNORMAL)
            if Int(bitPattern: result) <= 32 {
                FileHandle.standardError.write(
                    Data("tray: report folder not opened: \(Int(bitPattern: result))\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("tray: report not saved: \(error)\n".utf8))
        }
    }

    // openSettings opens the choices file with its default program, writing it first with the
    // current choices when it does not exist.
    private func openSettings() {
        if !FileManager.default.fileExists(atPath: app.store.url.path) {
            app.engine.save()
        }
        let result = ShellExecuteW(window, wide("open"), wide(app.store.url.path), nil, nil, SW_SHOWNORMAL)
        let code = Int(bitPattern: result)
        if code <= 32 {
            FileHandle.standardError.write(Data("tray: settings file not opened: \(code)\n".utf8))
        }
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
        return CreateIconFromResourceEx(
            &bytes, DWORD(best.length), true, 0x0003_0000,
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
