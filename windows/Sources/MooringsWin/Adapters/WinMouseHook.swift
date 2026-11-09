import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// WinMouseHook delivers the pointer through a low-level mouse hook on the loop thread. The hook
// callback posts the point and the button message to the thread and notes where the left button went
// down. A button press also asks takes whether the press is Moorings', and if so the hook swallows the
// press and its release. All of it stays far under the time Windows allows before it removes a slow
// hook.
final class WinMouseHook {
    // message is the private thread message the callback posts, with the mouse message in wParam
    // and the point packed in lParam. The tray icon has WM_APP + 1.
    static let message = UINT(WM_APP) + 2
    // heartbeatSeconds is how often the hook is checked for still delivering.
    static let heartbeatSeconds = 10.0
    // mouseLowLevel is WH_MOUSE_LL.
    static let mouseLowLevel: Int32 = 14
    // left is the left button's number. The others are numbered as the Mac numbers them: 2 middle,
    // 3 back and 4 forward.
    static let left = 0

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
    // takes reports whether a press of the numbered button at a point belongs to Moorings. The callback
    // calls it, which can happen while a pass waits on another process's window, so it may only read
    // and queue.
    nonisolated(unsafe) static var takes: (Int, POINT) -> Bool = { _, _ in false }
    // swallowing is false only in the buttons probe's negative control, which lets taken presses pass.
    nonisolated(unsafe) static var swallowing = true
    // swallowed holds the numbers of the buttons whose press the hook swallowed and whose release it
    // has yet to see.
    nonisolated(unsafe) static var swallowed: Set<Int> = []
    // slowest is the longest takes has run, in milliseconds by GetTickCount64.
    nonisolated(unsafe) static var slowest: UInt64 = 0

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
                    if wParam != WPARAM(WM_MOUSEMOVE), WinMouseHook.swallows(wParam, info.pointee) {
                        return 1
                    }
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

    // swallows reports whether the hook keeps message from every window. A press goes when takes claims
    // it, and a release goes only when its own press did, so a lost release cannot eat a later one.
    private static func swallows(_ message: WPARAM, _ info: MSLLHOOKSTRUCT) -> Bool {
        guard let button = button(message, data: info.mouseData) else { return false }
        guard button.down else { return swallowed.remove(button.number) != nil }
        swallowed.remove(button.number)
        let start = GetTickCount64()
        let taken = takes(button.number, info.pt)
        slowest = max(slowest, GetTickCount64() &- start)
        guard taken, swallowing else { return false }
        swallowed.insert(button.number)
        return true
    }

    // button returns the number of the button message names and whether it went down, nil for the right
    // button, which no binding takes, and for a message that is no button's. The high word of data says
    // which X button.
    static func button(_ message: WPARAM, data: DWORD) -> (number: Int, down: Bool)? {
        let extra = data >> 16 == 1 ? 3 : 4
        switch message {
        case WPARAM(WM_LBUTTONDOWN): return (left, true)
        case WPARAM(WM_LBUTTONUP): return (left, false)
        case WPARAM(WM_MBUTTONDOWN): return (2, true)
        case WPARAM(WM_MBUTTONUP): return (2, false)
        case WPARAM(WM_XBUTTONDOWN): return (extra, true)
        case WPARAM(WM_XBUTTONUP): return (extra, false)
        default: return nil
        }
    }

    // deliver handles msg when it is the hook's message and reports whether it was.
    func deliver(_ msg: MSG) -> Bool {
        guard msg.message == Self.message, msg.hwnd == nil else { return false }
        let x = Int32(truncatingIfNeeded: msg.lParam >> 32), y = Int32(truncatingIfNeeded: msg.lParam)
        let p = SnapPoint(Double(x), Double(y))
        point = p
        if msg.wParam == WPARAM(WM_LBUTTONDOWN) {
            WinDrag.classify(POINT(x: x, y: y), at: Self.press?.tick ?? GetTickCount64())
        }
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

    // began starts following hwnd, which the owner started moving or sizing. The press was classified
    // when the button went down, before the window under it could move: a press on hwnd within
    // pressMillis that hwnd answered HTCAPTION moves it, any other answer sizes it. With no such
    // press, or no answer, the follower decides from the first frame change. The cursor is never
    // read here, since a full-window drag has carried the window off the press point by now and a
    // window in its move loop can answer its own caption as client.
    func began(_ hwnd: HWND) {
        let last = Self.lastPress
        let press = last.flatMap { GetTickCount64() &- $0.tick <= Self.pressMillis && $0.root == hwnd ? $0 : nil }
        let moving = press.flatMap { p in p.answer.map { $0 == Self.caption } }
        let id = WinWindows.id(hwnd)
        if Self.verbose {
            let age = last.map { "\(GetTickCount64() &- $0.tick)" } ?? "none"
            let root = last?.root.map(WinWindows.className) ?? "none"
            print(
                "drag: began \(hex(id)) press \(last.map { "\($0.x) \($0.y)" } ?? "none") age \(age) ms",
                "root \(root) hit \(last?.answer.map { "\($0)" } ?? "none") moving \(moving.map { "\($0)" } ?? "nil")")
        }
        app.engine.drag.began(window: id, moving: moving, at: press.map { Point(x: Double($0.x), y: Double($0.y)) })
    }

    // Press is a left button press as the loop thread classified it when the hook delivered it.
    struct Press {
        // x is the press's horizontal position on the virtual desktop.
        var x: Int32
        // y is the press's vertical position on the virtual desktop.
        var y: Int32
        // tick is when the button went down, by GetTickCount64.
        var tick: UInt64
        // root is the top-level window under the press, nil over none.
        var root: HWND?
        // answer is root's WM_NCHITTEST answer at the press, nil when it gave none in time.
        var answer: DWORD_PTR?
    }

    // caption is HTCAPTION.
    static let caption: DWORD_PTR = 2
    // pressMillis is how long after the press a move or size may start and still be judged by the
    // press, the longest Windows waits on a low-level hook.
    static let pressMillis: UInt64 = 1000
    // lastPress is the last left button press, classified on the loop thread.
    nonisolated(unsafe) static var lastPress: Press?
    // verbose prints a drag line on each start, for the scenarios probe. The app never sets it.
    nonisolated(unsafe) static var verbose = false

    // classify records the press at p, made at tick, with the top-level window under it and that
    // window's hit test answer there.
    static func classify(_ p: POINT, at tick: UInt64) {
        let root = WindowFromPoint(p).flatMap { GetAncestor($0, WinWatcher.root) }
        lastPress = Press(x: p.x, y: p.y, tick: tick, root: root, answer: root.flatMap { hit($0, at: p) })
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
        let held = Modifiers.now()
        if held.contains(.command) {
            Self.maskKeys()
        }
        app.engine.drag.ended(held: held)
    }

    // maskKeys taps a key no keyboard has, so letting go of the Windows key does not open the Start
    // menu and letting go of Alt does not open the menu bar, which open only when no other key came
    // between the press and the release.
    static func maskKeys() {
        var inputs = [DWORD(0), DWORD(0x0002)].map { flags in
            var input = INPUT()
            input.type = DWORD(INPUT_KEYBOARD)
            input.ki.wVk = 0xE8
            input.ki.dwFlags = flags
            return input
        }
        _ = SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
    }
}
