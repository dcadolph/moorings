import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// WinMouseHook delivers the pointer through a low-level mouse hook on the loop thread. The hook
// callback only posts the point and the button message to the thread and notes where the left button
// went down, so it stays far under the time Windows allows before it removes a slow hook.
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
    // press is where the left button last went down on the virtual desktop and when, by
    // GetTickCount64. The callback writes it, so it is set before the window under the press hears it.
    nonisolated(unsafe) static var press: (x: Int32, y: Int32, tick: UInt64)?

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
        hook = SetWindowsHookExW(
            Self.mouseLowLevel,
            { code, wParam, lParam in
                if code >= 0, let info = UnsafePointer<MSLLHOOKSTRUCT>(bitPattern: Int(lParam)) {
                    WinMouseHook.delivered &+= 1
                    let p = info.pointee.pt
                    if wParam == WPARAM(WM_LBUTTONDOWN) {
                        WinMouseHook.press = (p.x, p.y, GetTickCount64())
                    }
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

// WinDrag feeds a window moved by its frame to the engine's DragFollower: the window's hit test at
// the press says move or size, the hook's pointer follows, and the drop runs at the hook's last point.
// Alt stands for the Mac's Option and the Windows key for Command.
final class WinDrag {
    // app holds the engine's follower and the hook.
    private unowned let app: App

    // init builds the glue for app.
    init(app: App) {
        self.app = app
    }

    // began starts following hwnd, which the owner started moving or sizing. The caption moves and a
    // border sizes; with no answer the follower decides from the first frame change. When Windows
    // drags an outline the window stays put until the drop, so the hit test reads the point where the
    // button went down on hwnd: by the time a busy loop hears the start, the cursor can have left the
    // caption. A full-window drag carries the caption under the cursor, so it reads the cursor.
    func began(_ hwnd: HWND) {
        let press = Self.press(on: hwnd)
        var cursor = POINT()
        let point = (Self.fullDrag ? nil : press) ?? (GetCursorPos(&cursor) ? cursor : nil)
        app.engine.drag.began(
            window: WinWindows.id(hwnd), moving: point.flatMap { Self.hit(hwnd, at: $0) }.map { $0 == Self.caption },
            at: press.map { Point(x: Double($0.x), y: Double($0.y)) })
    }

    // caption is HTCAPTION.
    static let caption: DWORD_PTR = 2
    // pressMillis is how long after the press a move or size may start and still be judged at the
    // press point, the longest Windows waits on a low-level hook.
    static let pressMillis: UInt64 = 1000

    // press returns where the left button last went down when that was on hwnd within pressMillis,
    // nil otherwise.
    static func press(on hwnd: HWND) -> POINT? {
        guard let p = WinMouseHook.press, GetTickCount64() &- p.tick <= pressMillis else { return nil }
        let point = POINT(x: p.x, y: p.y)
        guard let child = WindowFromPoint(point), GetAncestor(child, WinWatcher.root) == hwnd else { return nil }
        return point
    }

    // fullDrag reports whether Windows moves the whole window during a drag rather than an outline.
    static var fullDrag: Bool {
        var full: WindowsBool = false
        _ = SystemParametersInfoW(UINT(SPI_GETDRAGFULLWINDOWS), 0, &full, 0)
        return full.boolValue
    }

    // hit returns hwnd's answer to WM_NCHITTEST at p, nil when the window gives no answer inside 100 ms.
    static func hit(_ hwnd: HWND, at p: POINT) -> DWORD_PTR? {
        let x = UInt32(UInt16(truncatingIfNeeded: p.x)), y = UInt32(UInt16(truncatingIfNeeded: p.y))
        var result: DWORD_PTR = 0
        guard
            SendMessageTimeoutW(
                hwnd, UINT(WM_NCHITTEST), 0, LPARAM(Int32(bitPattern: x | y << 16)),
                UINT(SMTO_ABORTIFHUNG), 100, &result) != 0
        else { return nil }
        return result
    }

    // pointer follows the pointer at p while a drag is under way.
    func pointer(_ p: SnapPoint) {
        app.engine.drag.moved(Point(x: p.x, y: p.y), held: Modifiers.now())
    }

    // ended runs the drop at the hook's last point once the drag ends.
    func ended() {
        guard let p = app.mouse.point else {
            app.engine.drag.cancel()
            return
        }
        pointer(p)
        app.engine.drag.ended(held: Modifiers.now())
    }
}
