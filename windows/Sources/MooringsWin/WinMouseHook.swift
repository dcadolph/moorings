import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

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
        hook = SetWindowsHookExW(
            Self.mouseLowLevel,
            { code, wParam, lParam in
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

// WinDrag feeds a window moved by its frame to the engine's DragFollower: the window's hit test at
// the press says move or size, the hook's pointer follows, and the drop runs at the hook's last point.
// Alt stands for the Mac's Option and the Windows key for Command.
final class WinDrag {
    // app holds the follower and the hook.
    private unowned let app: App
    // dropped is told each finished drag, the window and what it dropped on.
    var dropped: (WindowID, SnapDrop?) -> Void {
        get { app.follower.dropped }
        set { app.follower.dropped = newValue }
    }

    // init builds the glue for app.
    init(app: App) {
        self.app = app
    }

    // began starts following hwnd, which the owner started moving or sizing. The caption moves and a
    // border sizes; with no answer the follower decides from the first frame change.
    func began(_ hwnd: HWND) {
        app.follower.began(window: WinWindows.id(hwnd), moving: Self.hit(hwnd).map { $0 == Self.caption })
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
        guard
            SendMessageTimeoutW(
                hwnd, UINT(WM_NCHITTEST), 0, LPARAM(Int32(bitPattern: x | y << 16)),
                UINT(SMTO_ABORTIFHUNG), 100, &result) != 0
        else { return nil }
        return result
    }

    // pointer follows the pointer at p while a drag is under way.
    func pointer(_ p: SnapPoint) {
        app.follower.moved(Point(x: p.x, y: p.y), held: Modifiers.now())
    }

    // ended runs the drop at the hook's last point once the drag ends.
    func ended() {
        guard let p = app.mouse.point else {
            app.follower.cancel()
            return
        }
        pointer(p)
        app.follower.ended(held: Modifiers.now())
    }
}
