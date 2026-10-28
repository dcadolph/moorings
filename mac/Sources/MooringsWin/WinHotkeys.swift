import Foundation
import WinSDK

import MooringsCore

// WinHotkeys registers the window action shortcuts with RegisterHotKey for the thread that runs
// the message loop, which then receives WM_HOTKEY for each press.
final class WinHotkeys {
    // keyCodes maps each key name to its virtual key code. Delete is Backspace, the key a Mac
    // keyboard labels delete, and forwarddelete is Delete.
    static let keyCodes: [String: UINT] = {
        var out: [String: UINT] = [
            "=": 0xBB, "-": 0xBD, "[": 0xDB, "]": 0xDD, ";": 0xBA, "'": 0xDE, ",": 0xBC, ".": 0xBE,
            "/": 0xBF, "\\": 0xDC, "`": 0xC0, "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
            "return": 0x0D, "enter": 0x0D, "delete": 0x08, "forwarddelete": 0x2E, "escape": 0x1B,
            "tab": 0x09, "space": 0x20, "home": 0x24, "end": 0x23, "pageup": 0x21, "pagedown": 0x22,
        ]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            out[String(c)] = UINT(0x41 + i)
        }
        for i in 0...9 {
            out["\(i)"] = UINT(0x30 + i)
        }
        for i in 1...20 {
            out["f\(i)"] = UINT(0x6F + i)
        }
        return out
    }()
    // modifierFlags maps each modifier to its RegisterHotKey flag. Command is the Windows key.
    static let modifierFlags: [Modifier: UINT] = [
        .alt: 0x0001, .ctrl: 0x0002, .shift: 0x0004, .cmd: 0x0008,
    ]
    // noRepeat is MOD_NOREPEAT, so holding a chord runs its action once.
    static let noRepeat: UINT = 0x4000
    // alreadyRegistered is ERROR_HOTKEY_ALREADY_REGISTERED.
    static let alreadyRegistered: DWORD = 1409
    // arrows are the arrow keys, which the shell owns with the Windows key alone or with Shift.
    static let arrows: Set = ["left", "right", "up", "down"]
    // keyNames maps a key name to the name printed on a Windows keyboard.
    private static let keyNames: [String: String] = [
        "left": "Left", "right": "Right", "up": "Up", "down": "Down", "return": "Enter",
        "enter": "Enter", "delete": "Backspace", "forwarddelete": "Delete", "escape": "Esc",
        "tab": "Tab", "space": "Space", "home": "Home", "end": "End", "pageup": "Page Up",
        "pagedown": "Page Down",
    ]
    // modifierNames maps each modifier to the name printed on a Windows keyboard.
    private static let modifierNames: [Modifier: String] = [
        .ctrl: "Ctrl", .alt: "Alt", .shift: "Shift", .cmd: "Win",
    ]

    // run is called with the action name of a pressed shortcut.
    private let run: (String) -> Void
    // names maps each registered hotkey id to its action name.
    private(set) var names: [Int32: String] = [:]
    // skipped lists each shortcut not registered by action name, with the reason.
    private(set) var skipped: [(name: String, reason: String)] = []
    // pressed lists the action names of the presses received, in order.
    private(set) var pressed: [String] = []

    // init builds hotkeys that call run with the action name of each press.
    init(run: @escaping (String) -> Void) {
        self.run = run
    }

    // spelled returns the shortcut the way Windows writes one, such as Ctrl+Alt+Left.
    static func spelled(_ sc: Shortcut) -> String {
        let key = keyNames[sc.key] ?? sc.key.uppercased()
        return (sc.mods.compactMap { modifierNames[$0] } + [key]).joined(separator: "+")
    }

    // shellOwns reports whether Windows keeps sc for itself: the Windows key with an arrow, alone
    // or with Shift, snaps and moves windows between displays.
    static func shellOwns(_ sc: Shortcut) -> Bool {
        sc.mods.contains(.cmd) && !sc.mods.contains(.ctrl) && !sc.mods.contains(.alt)
            && arrows.contains(sc.key)
    }

    // bind registers map, replacing what was bound before. A shortcut whose action Windows cannot
    // run yet, whose key Windows has no code for, that the shell owns, or that another program
    // holds is skipped and logged.
    func bind(_ map: [String: Shortcut], runnable: (String) -> Bool) {
        unbind()
        var id: Int32 = 0
        for (name, sc) in map.sorted(by: { $0.key < $1.key }) {
            guard runnable(name) else {
                skip(name, sc, "not on Windows yet")
                continue
            }
            guard let vk = Self.keyCodes[sc.key] else {
                skip(name, sc, "no such key on Windows")
                continue
            }
            if Self.shellOwns(sc) {
                skip(name, sc, "Windows keeps it")
                continue
            }
            id += 1
            let mods = sc.mods.reduce(Self.noRepeat) { $0 | (Self.modifierFlags[$1] ?? 0) }
            guard RegisterHotKey(nil, id, mods, vk) else {
                let error = GetLastError()
                let held = error == Self.alreadyRegistered
                skip(name, sc, held ? "another program holds it" : "error \(error)")
                continue
            }
            names[id] = name
        }
    }

    // unbind removes every registered shortcut.
    func unbind() {
        for id in names.keys {
            _ = UnregisterHotKey(nil, id)
        }
        names = [:]
        skipped = []
    }

    // fire runs the action of the hotkey a WM_HOTKEY message names.
    func fire(_ wParam: WPARAM) {
        guard let name = names[Int32(truncatingIfNeeded: wParam)] else { return }
        pressed.append(name)
        run(name)
    }

    // skip records name's shortcut sc as not registered and logs why.
    private func skip(_ name: String, _ sc: Shortcut, _ reason: String) {
        skipped.append((name, reason))
        let line = "hotkeys: \(name) \(Self.spelled(sc)) skipped: \(reason)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

// WinActions applies window actions to the foreground window the way the Mac ActionRunner does
// for the actions that place a frame: halves, thirds, sizes, displays, arrow mode, fill, restore,
// undo and redo. The actions on the front app, stash, organize, tiling, workspaces, profiles,
// chains, the grid and the menus wait for later phases.
final class WinActions {
    // app runs the passes and holds the layout the actions read.
    private unowned let app: App
    // last records the last action applied to each window, so a repeat press steps its cycle.
    private var last: [WindowID: LastPress] = [:]

    // init builds actions for app.
    init(app: App) {
        self.app = app
    }

    // anchors is the layout the actions read.
    private var anchors: Anchors { app.anchors }

    // supports reports whether name is an action Windows runs.
    func supports(_ name: String) -> Bool {
        let later = Keymaps.windowNames.contains(name) || Keymaps.stashNames.contains(name)
            || Tile.handles(name) || Tiling.handles(name) || name.hasPrefix(Keymaps.workspacePrefix)
            || name.hasPrefix(Profile.prefix) || name.hasPrefix(Chain.prefix)
            || name == Keymaps.menuName || name == Keymaps.stripsName
            || Overlay.gridSize(name, anchors.choices.overlay) != nil
        return !later && (Keymaps.known(name) || Bindings(anchors.choices).specs[name] != nil)
    }

    // run applies action name to the foreground window and reports whether anything moved.
    @discardableResult
    func run(_ name: String) -> Bool {
        guard !anchors.choices.paused, supports(name) else { return false }
        last = last.filter { entry in WinWindows.hwnd(entry.key).map { IsWindow($0) } ?? false }
        let screens = Screens.current(minAspect: app.minAspect)
        let focused = WinWindows.scan(screens: screens).focused
        guard let w = focused, !app.windows.elevated.contains(w.id) else {
            log("\(name): no foreground window Moorings can move")
            return false
        }
        guard apply(name, to: w, screens: screens) else { return false }
        if anchors.choices.behavior.moveCursor, let f = app.windows.frame(w.id) {
            _ = SetCursorPos(Int32((f.x + f.w / 2).rounded()), Int32((f.y + f.h / 2).rounded()))
        }
        return true
    }

    // apply applies action name to window w and reports whether it moved. On a pin, Maximize lifts
    // or lowers it and Restore re-moors it; every other action leaves a pin alone.
    private func apply(_ name: String, to w: WindowInfo, screens: Screens) -> Bool {
        guard !screens.full.isEmpty else { return false }
        if anchors.pinned(w) {
            switch name {
            case "maximize":
                anchors.toggleLift(w)
            case "restore":
                anchors.remoor(w.id)
            default:
                log("the window is pinned: window actions leave pins alone")
                return false
            }
            app.wake()
            app.moor()
            return true
        }
        if w.isFullScreen {
            return false
        }
        if name == "restore" {
            last[w.id] = nil
            guard let f = anchors.restore(w.id) else { return false }
            anchors.history.record(w.id, from: w.frame)
            app.windows.move(w.id, to: f)
            app.wake()
            return true
        }
        if name == "undo-move" || name == "redo-move" {
            last[w.id] = nil
            let f = name == "undo-move" ? anchors.history.undo(w.id, current: w.frame)
                : anchors.history.redo(w.id, current: w.frame)
            guard let f else {
                log("\(name): nothing to step to for this window")
                return false
            }
            app.windows.move(w.id, to: f)
            app.wake()
            return true
        }
        let target = target(for: w, screens: screens)
        if Actions.arrowNames.contains(name) {
            switch Actions.arrow(name, cur: w.frame, target: target, gap: anchors.choices.gapPx,
                                 behavior: anchors.choices.behavior) {
            case let .frame(f, landed):
                return place(w, at: f, press: 1, name: landed)
            case .restore:
                return apply("restore", to: w, screens: screens)
            case .minimize:
                if let hwnd = WinWindows.hwnd(w.id) {
                    _ = ShowWindow(hwnd, SW_MINIMIZE)
                }
                return true
            case .stay:
                return false
            }
        }
        if Behavior.restoresMaximize(name, cur: w.frame, last: last[w.id], anchors.choices.behavior) {
            return apply("restore", to: w, screens: screens)
        }
        if Actions.fillNames.contains(name) {
            let area = Actions.area(target, target.index, anchors.choices.behavior)
            let others = WinWindows.scan(screens: screens).windows.filter { $0.id != w.id }
            let f = Geometry.fill(w.frame, name == "fill-left" ? .left : .right, area: area,
                                  others: others.map(\.frame), gap: anchors.choices.gapPx)
            return f == w.frame ? false : place(w, at: f, press: 1, name: name)
        }
        let choices = anchors.choices
        let (frame, press, result) = Actions.frame(name, cur: w.frame, target: target, gap: choices.gapPx,
                                                   sizes: Bindings(choices).specs, last: last[w.id],
                                                   behavior: choices.behavior)
        guard let frame else { return false }
        return place(w, at: frame, press: press, name: result)
    }

    // place moves w to frame and records it as press of action name, so a repeat press steps on.
    private func place(_ w: WindowInfo, at frame: Frame, press: Int, name: String) -> Bool {
        anchors.save(w)
        app.windows.move(w.id, to: frame)
        let landed = app.windows.frame(w.id) ?? frame
        last[w.id] = LastPress(name: name, press: press, frame: landed)
        app.landed(w.id, at: landed)
        app.wake()
        return true
    }

    // target returns the screens an action on w may use: the channel on the ultrawide and the usable
    // frame elsewhere, with w on its own screen.
    private func target(for w: WindowInfo, screens: Screens) -> ActionTarget {
        let areas = screens.usable.indices.map { i in
            i == screens.ultrawide ? anchors.channel(screens.usable[i]) : screens.usable[i]
        }
        return ActionTarget(screens: screens.full, areas: areas, index: screens.index(w.frame) ?? 0)
    }

    // log writes why an action did nothing to stderr.
    private func log(_ line: String) {
        FileHandle.standardError.write(Data("actions: \(line)\n".utf8))
    }
}
