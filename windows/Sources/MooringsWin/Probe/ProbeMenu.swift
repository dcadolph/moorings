import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeMenu prints the tray menu the saved choices and the running windows build, one entry per
// line, indented by depth, with [x] beside a checked entry.
func probeMenu(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let running = opts.noApps ? [] : WinWindows.scan(screens: screens).windows.map(\.bundle)
    printMenu(
        Tray.menu(
            choices: Store().load().choices, running: running, atLogin: LoginItem.enabled,
            isUltrawide: screens.isUltrawide))
    return 0
}

// menuChord is Ctrl+Alt+Shift+F9, the shortcut the pointer menu probe binds show-menu to.
let menuChord = StoredShortcut(mods: ["ctrl", "alt", "shift"], key: "f9")

// menuPointer is where the pointer menu probe puts the pointer before it presses the chord.
let menuPointer = (x: Int32(300), y: Int32(200))

// probePointerMenu binds show-menu to menuChord on a fresh choices file, shows the tray, brings the
// front window of the app forward and puts the pointer at menuPointer. A second thread presses the
// chord, since only a process that took the last input may take the foreground the menu needs,
// waits for the popup menu, prints its frame and the foreground while it is open, cancels it, and
// prints the foreground after it closed.
func probePointerMenu(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let pad = WinWindows.scan(screens: screens).windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("pointermenu: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    var choices = Choices()
    choices.shortcuts[Keymaps.menuName] = menuChord
    do {
        try store.save(choices)
    } catch {
        print("pointermenu: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let tray = Tray(app: app)
    defer { tray.hide() }
    guard tray.show(), let trayWindow = tray.window else {
        print("pointermenu: no tray")
        return 1
    }
    let map = Bindings(app.engine.anchors.choices).map
    app.hotkeys.bind(map, runnable: app.engine.actions.supports)
    defer { app.hotkeys.unbind() }
    let bound = app.hotkeys.names.values.contains(Keymaps.menuName)
    print("chord: \(map[Keymaps.menuName].map(WinHotkeys.spelled) ?? "none") bound \(bound)")
    for s in app.hotkeys.skipped where s.name == Keymaps.menuName {
        print("skipped \(s.name): \(s.reason)")
    }
    _ = bringForward(hwnd)
    _ = SetCursorPos(menuPointer.x, menuPointer.y)
    print("pointer: \(menuPointer.x) \(menuPointer.y)")
    print("notepad: \(hex(pad.id)) tray: \(hex(WinWindows.id(trayWindow)))")
    print("foreground before: \(foreground())")
    let loop = GetCurrentThreadId()
    let trayBits = UInt(bitPattern: trayWindow)
    Thread {
        Sleep(1000)
        print("sent: \(press([0x11, 0x12, 0x10, 0x78]))")
        var popup: HWND?
        for _ in 0..<30 where popup == nil {
            Sleep(100)
            popup = FindWindowW(wide("#32768"), nil).flatMap { IsWindowVisible($0) ? $0 : nil }
        }
        if let popup {
            var r = RECT()
            _ = GetWindowRect(popup, &r)
            print("menu: \(r.left) \(r.top) \(r.right - r.left) \(r.bottom - r.top)")
        } else {
            print("menu: none")
        }
        print("foreground open: \(foreground())")
        if let owner = HWND(bitPattern: trayBits) {
            _ = PostMessageW(owner, UINT(WM_CANCELMODE), 0, 0)
        }
        Sleep(1000)
        let left = FindWindowW(wide("#32768"), nil).map { IsWindowVisible($0) ? "shown" : "hidden" }
        print("menu after: \(left ?? "none")")
        print("foreground after: \(foreground())")
        _ = PostThreadMessageW(loop, UINT(WM_QUIT), 0, 0)
    }.start()
    app.run(until: App.now + opts.seconds)
    let pressed = app.hotkeys.pressed
    print("hotkeys received: \(pressed.isEmpty ? "none" : pressed.joined(separator: ","))")
    return 0
}

// printMenu prints items and their folders, depth levels in.
func printMenu(_ items: [MenuItem], depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    for item in items {
        guard !item.title.isEmpty else {
            print("menu \(indent)-")
            continue
        }
        print("menu \(indent)[\(item.checked ? "x" : " ")] \(item.title)\(item.enabled ? "" : " (off)")")
        printMenu(item.submenu, depth: depth + 1)
    }
}
