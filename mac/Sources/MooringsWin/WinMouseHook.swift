import Foundation
import WinSDK

import MooringsCore

// WinMouseHook delivers the pointer through a low-level mouse hook on the loop thread. The hook
// callback only posts the point and the button message to the thread, so it stays far under the
// time Windows allows before it removes a slow hook.
final class WinMouseHook {
    // message is the private thread message the callback posts, with the mouse message in wParam
    // and the point packed in lParam. The tray icon has WM_APP + 1.
    static let message = UINT(WM_APP) + 2
    // heartbeatSeconds is how often the hook is checked for still delivering.
    static let heartbeatSeconds = 10.0
    // mouseLowLevel is WH_MOUSE_LL.
    static let mouseLowLevel: Int32 = 14

    // point is the last point the hook delivered, nil before the first.
    private(set) var point: SnapPoint?
    // reinstalls counts the times the heartbeat found the hook silent and put it back.
    private(set) var reinstalls = 0
    // handler runs on each delivered mouse message with the message and the point.
    var handler: (UINT, SnapPoint) -> Void = { _, _ in }
    // hook is the installed hook, nil when none is.
    private var hook: HHOOK?
    // timer is the heartbeat timer's id, 0 when none.
    private(set) var timer: UINT_PTR = 0
    // seen is the delivery count at the last heartbeat.
    private var seen = 0
    // cursor is where the cursor was at the last heartbeat, nil before the first.
    private var cursor: POINT?

    // thread is the loop thread the callback posts to, which it reaches since it cannot capture.
    nonisolated(unsafe) static var thread: DWORD = 0
    // delivered counts the messages the callback posted.
    nonisolated(unsafe) static var delivered = 0

    // start installs the hook for the calling thread and starts the heartbeat.
    func start() {
        guard hook == nil else { return }
        Self.thread = GetCurrentThreadId()
        install()
        timer = SetTimer(nil, 0, UINT(Self.heartbeatSeconds * 1000), nil)
    }

    // stop removes the hook and the heartbeat.
    func stop() {
        if let hook {
            _ = UnhookWindowsHookEx(hook)
        }
        hook = nil
        if timer != 0 {
            _ = KillTimer(nil, timer)
        }
        timer = 0
    }

    // install sets the hook and reports whether Windows took it.
    @discardableResult
    private func install() -> Bool {
        hook = SetWindowsHookExW(Self.mouseLowLevel, { code, wParam, lParam in
            if code >= 0, let info = UnsafePointer<MSLLHOOKSTRUCT>(bitPattern: Int(lParam)) {
                WinMouseHook.delivered &+= 1
                let p = info.pointee.pt
                let packed = LPARAM(Int(p.x) << 32 | Int(UInt32(bitPattern: p.y)))
                _ = PostThreadMessageW(WinMouseHook.thread, WinMouseHook.message, wParam, packed)
            }
            return CallNextHookEx(nil, code, wParam, lParam)
        }, GetModuleHandleW(nil), 0)
        return hook != nil
    }

    // deliver handles msg when it is the hook's message and reports whether it was.
    func deliver(_ msg: MSG) -> Bool {
        guard msg.message == Self.message, msg.hwnd == nil else { return false }
        let x = Int32(truncatingIfNeeded: msg.lParam >> 32), y = Int32(truncatingIfNeeded: msg.lParam)
        let p = SnapPoint(Double(x), Double(y))
        point = p
        handler(UINT(msg.wParam), p)
        return true
    }

    // tick runs the heartbeat when id is its timer and reports whether it was.
    func tick(_ id: UINT_PTR) -> Bool {
        guard timer != 0, id == timer else { return false }
        heartbeat()
        return true
    }

    // heartbeat puts the hook back once when the cursor moved since the last heartbeat and the hook
    // delivered nothing, which is how a hook Windows removed looks.
    private func heartbeat() {
        var now = POINT()
        guard GetCursorPos(&now) else { return }
        if let last = cursor, last.x != now.x || last.y != now.y, Self.delivered == seen {
            if let hook {
                _ = UnhookWindowsHookEx(hook)
            }
            install()
            reinstalls += 1
            FileHandle.standardError.write(Data("hook reinstalled\n".utf8))
        }
        cursor = now
        seen = Self.delivered
    }
}

// WinDrag follows a window moved by its frame: while it moves, the pointer from the hook picks the
// zone or slot the core's Snap gives, and on the drop the zone's action runs or, with Alt held on a
// strip, the window's app is anchored there, the Option-drop of the Mac.
final class WinDrag {
    // app runs the passes, the actions and the layout the drop reads.
    private unowned let app: App
    // dropped is told each finished drag, the window and what it dropped on.
    var dropped: (WindowID, SnapDrop?) -> Void = { _, _ in }
    // id is the dragged window, nil when no drag is under way.
    private var id: WindowID?
    // start is the dragged window's frame when the drag began.
    private var start: Frame?
    // moving is true for a drag that moves the window and false for one that sizes it. The window's
    // hit test at the press decides it: the caption moves, a border sizes. When the hit test gets no
    // answer, the first frame change decides it, a move when the size held, since Windows snapping a
    // window at a screen edge resizes it on the drop. Without window contents shown while dragging
    // the frame holds until the drop, so the hit test comes first.
    private var moving: Bool?
    // drop is the zone or slot under the pointer.
    private(set) var drop: SnapDrop?

    // init builds a drag follower for app.
    init(app: App) {
        self.app = app
    }

    // began starts following hwnd, which the owner started moving or sizing.
    func began(_ hwnd: HWND) {
        id = WinWindows.id(hwnd)
        start = WinWindows.bounds(hwnd)
        moving = Self.hit(hwnd).map { $0 == Self.caption }
        drop = nil
    }

    // caption is HTCAPTION.
    static let caption: DWORD_PTR = 2

    // hit returns hwnd's answer to WM_NCHITTEST at the cursor, nil when the cursor cannot be read or
    // the window gives no answer inside 100 ms.
    static func hit(_ hwnd: HWND) -> DWORD_PTR? {
        var p = POINT()
        guard GetCursorPos(&p) else { return nil }
        let x = UInt32(UInt16(truncatingIfNeeded: p.x)), y = UInt32(UInt16(truncatingIfNeeded: p.y))
        var result: DWORD_PTR = 0
        guard SendMessageTimeoutW(hwnd, UINT(WM_NCHITTEST), 0, LPARAM(Int32(bitPattern: x | y << 16)),
                                  UINT(SMTO_ABORTIFHUNG), 100, &result) != 0 else { return nil }
        return result
    }

    // pointer follows the pointer at p while a drag is under way.
    func pointer(_ p: SnapPoint) {
        guard let id else { return }
        if moving == nil, let start, let f = app.windows.frame(id), f != start {
            moving = abs(f.w - start.w) <= 1 && abs(f.h - start.h) <= 1
        }
        guard moving == true else { return }
        update(p, option: Self.down(Self.alt))
    }

    // ended runs the drop at the hook's last point once the drag ends, when the drag moved the
    // window.
    func ended() {
        defer {
            id = nil
            start = nil
            moving = nil
            drop = nil
        }
        guard let id, moving == true, let p = app.mouse.point else { return }
        guard let w = update(p, option: Self.down(Self.alt)) else { return }
        let drop = self.drop
        defer { dropped(id, drop) }
        switch drop {
        case let .park(key):
            guard let slot = SlotKey(rawValue: key) else { return }
            app.anchors.assign(slot, w.bundle)
            app.notify("\(Tray.appName(w.bundle)) anchored", "It holds the \(slot.title.lowercased()) slot now. "
                + "Unanchor it from the Moorings menu to free the slot.")
            app.save()
            app.wake()
        case let .zone(name):
            app.actions.apply(name, to: w, screens: Screens.current(minAspect: app.minAspect))
        case .none:
            break
        }
    }

    // update sets the drop for a pointer at p with option standing for Alt, and returns the dragged
    // window as a pass would read it, nil when it cannot be read.
    @discardableResult
    private func update(_ p: SnapPoint, option: Bool) -> WindowInfo? {
        let choices = app.anchors.choices
        let screens = Screens.current(minAspect: app.minAspect)
        guard let id, let hwnd = WinWindows.hwnd(id), let w = WinWindows.describe(hwnd, screens: screens) else {
            drop = nil
            return nil
        }
        guard !choices.paused, choices.snap, let i = screens.full.firstIndex(where: {
            p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h
        }) else {
            drop = nil
            return w
        }
        let ch = i == screens.ultrawide ? app.anchors.channel(screens.usable[i]) : nil
        var prev: String?
        if case let .zone(z) = drop {
            prev = z
        }
        drop = Snap.drop(p, screens.full[i], ch, prev: prev, option: option, parkable: true,
                         pinned: app.anchors.pinned(w), castOff: app.anchors.isCastOff(w.id),
                         snapping: choices.snapping, held: Self.held())
        return w
    }

    // alt is VK_MENU.
    static let alt: Int32 = 0x12

    // down reports whether the virtual key vk is held now.
    static func down(_ vk: Int32) -> Bool {
        GetAsyncKeyState(vk) < 0
    }

    // held returns the names of the snap modifiers held now, the Windows key standing for command.
    static func held() -> Set<String> {
        let keys: [(Int32, String)] = [(0x10, "shift"), (0x11, "control"), (alt, "option"), (0x5B, "command"),
                                       (0x5C, "command")]
        return Set(keys.filter { down($0.0) }.map(\.1))
    }
}
