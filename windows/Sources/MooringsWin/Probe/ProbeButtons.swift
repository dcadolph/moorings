import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// ButtonSpot is where a button probe case presses.
enum ButtonSpot: Sendable {
    // middle is the middle of the window.
    case middle
    // answer is the part of the caption that answers this to WM_NCHITTEST.
    case answer(DWORD_PTR)
}

// ButtonCase is one press the buttons probe makes on a window at its known start.
struct ButtonCase: Sendable {
    // name is the case's name on its printed line.
    var name: String
    // keys are held through the press.
    var keys: [WORD] = []
    // spot is where the press lands.
    var spot: ButtonSpot
    // flags are the SendInput flags for the button going down and coming up.
    var flags: (down: DWORD, up: DWORD) = (0x0002, 0x0004)
    // data says which X button.
    var data: DWORD = 0
    // behind presses with the other window in front.
    var behind = false
}

// buttonStart is where every case starts its window, on any screen the runner has.
let buttonStart = (x: Int32(200), y: Int32(150), w: Int32(500), h: Int32(350))
// buttonOtherStart is where the other window waits, clear of the first window's caption.
let buttonOtherStart = (x: Int32(100), y: Int32(520), w: Int32(400), h: Int32(150))

// buttonCases lists the presses. The bound ones expect the choices probeButtons saves. Close comes last,
// so a press that gets through ends the window after every other case has been read.
let buttonCases = [
    ButtonCase(name: "back", spot: .middle, flags: (0x0080, 0x0100), data: 1),
    ButtonCase(name: "forward", spot: .middle, flags: (0x0080, 0x0100), data: 2),
    ButtonCase(name: "middle", spot: .middle, flags: (0x0020, 0x0040)),
    ButtonCase(name: "shift-maximize", keys: [0x10], spot: .answer(9)),
    ButtonCase(name: "alt-minimize", keys: [0x12], spot: .answer(8)),
    ButtonCase(name: "behind", keys: [0x10], spot: .answer(9), behind: true),
    ButtonCase(name: "shift-caption", keys: [0x10], spot: .answer(2)),
    ButtonCase(name: "plain-maximize", spot: .answer(9)),
    ButtonCase(name: "plain-minimize", spot: .answer(8)),
    ButtonCase(name: "windows-close", keys: [0x5B], spot: .answer(20)),
]

// captionSpot finds the middle of the part of hwnd's caption that answers answer, nil when none does.
// It walks the caption rows from the top right, since no two windows place their buttons alike.
func captionSpot(_ hwnd: HWND, _ answer: DWORD_PTR) -> POINT? {
    var r = RECT()
    guard GetWindowRect(hwnd, &r) else { return nil }
    for y in stride(from: r.top + 6, to: r.top + 42, by: 6) {
        let run = stride(from: r.right - 2, to: r.left, by: -4).filter { x in
            WinDrag.hit(hwnd, at: POINT(x: x, y: y)) == answer
        }
        if let first = run.first, let last = run.last {
            return POINT(x: (first + last) / 2, y: y)
        }
    }
    return nil
}

// buttonLine prints the case's name with hwnd's frame and state.
func buttonLine(_ name: String, _ id: WindowID) {
    guard let hwnd = WinWindows.hwnd(id), IsWindow(hwnd) else {
        print("case \(name): gone")
        return
    }
    let yes = { (on: Bool) in on ? "yes" : "no" }
    print(
        "case \(name): frame \(WinWindows().frame(id).map(pixels) ?? "none")",
        "zoomed \(yes(IsZoomed(hwnd))) minimized \(yes(IsIconic(hwnd)))",
        "front \(yes(GetForegroundWindow() == hwnd))")
}

// runButtonCase puts the window at its start, presses as the case says, lets the result land and prints
// it. It runs on the probe's input thread, so it holds only window ids.
func runButtonCase(_ c: ButtonCase, _ id: WindowID, other: WindowID?) {
    guard let hwnd = WinWindows.hwnd(id) else { return }
    _ = ShowWindow(hwnd, SW_RESTORE)
    Sleep(200)
    _ = SetWindowPos(hwnd, nil, buttonStart.x, buttonStart.y, buttonStart.w, buttonStart.h, UINT(SWP_NOZORDER))
    bringForward(hwnd)
    if c.behind, let other, let front = WinWindows.hwnd(other) {
        _ = SetWindowPos(
            front, nil, buttonOtherStart.x, buttonOtherStart.y, buttonOtherStart.w, buttonOtherStart.h,
            UINT(SWP_NOZORDER))
        bringForward(front)
    }
    Sleep(500)
    var r = RECT()
    _ = GetWindowRect(hwnd, &r)
    let spot: POINT?
    switch c.spot {
    case .middle: spot = POINT(x: (r.left + r.right) / 2, y: (r.top + r.bottom) / 2)
    case let .answer(answer): spot = captionSpot(hwnd, answer)
    }
    guard let spot else {
        print("case \(c.name): no spot")
        return
    }
    sendMouse(spot.x, spot.y, 0)
    Sleep(100)
    c.keys.forEach { sendKey($0, up: false) }
    Sleep(50)
    sendMouse(spot.x, spot.y, c.flags.down, data: c.data)
    Sleep(200)
    sendMouse(spot.x, spot.y, c.flags.up, data: c.data)
    Sleep(50)
    c.keys.reversed().forEach { sendKey($0, up: true) }
    Sleep(800)
    buttonLine(c.name, id)
    if c.behind, let other {
        buttonLine("\(c.name) front window", other)
    }
}

// probeButtons binds the extra mouse buttons and three caption buttons, runs the loop while another
// thread makes each press in buttonCases on the window of --pid, and prints what each did, the channel
// and the slowest the hook decided. --no-swallow lets taken presses through and --paused saves paused
// choices, the two negative controls, and neither runs the close press, which would end the window.
func probeButtons(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.hostFrame, let pid = opts.pid, let hwnd = windowOf(pid, screens: screens) else {
        print("buttons: no ultrawide or no window of --pid")
        return 1
    }
    var choices = Choices()
    choices.paused = opts.paused
    choices.mouseButtons = ["2": "left-half", "3": "left-half", "4": "right-half"]
    choices.buttonClicks = ["green+shift": "left-half", "yellow+option": "right-half", "red+command": "left-half"]
    let store = Store()
    do {
        try store.save(choices)
    } catch {
        print("buttons: \(error)")
        return 1
    }
    WinMouseHook.swallowing = !opts.noSwallow
    let controls = opts.noSwallow || opts.paused
    let cases = controls ? buttonCases.filter { $0.name != "windows-close" } : buttonCases
    let id = WinWindows.id(hwnd)
    let other = opts.other.flatMap { windowOf($0, screens: screens) }.map(WinWindows.id)
    let app = App(store: store, minAspect: opts.minAspect)
    let loop = GetCurrentThreadId()
    Thread {
        Sleep(1000)
        cases.forEach { runButtonCase($0, id, other: other) }
        _ = PostThreadMessageW(loop, UINT(WM_QUIT), 0, 0)
    }.start()
    app.run(until: App.now + opts.seconds)
    print("channel: \(pixels(app.engine.anchors.channel(wide)))")
    print("hook slowest: \(WinMouseHook.slowest) ms")
    return 0
}

// probeCaptions prints what each window on screen answers at its three caption buttons, by class, so
// the runner can say which kinds of window take bound clicks. Any answer but a button keeps its native
// clicks.
func probeCaptions(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    for hwnd in WinWindows.topLevel() where WinWindows.describe(hwnd, screens: screens) != nil {
        let found = [("yellow", DWORD_PTR(8)), ("green", DWORD_PTR(9)), ("red", DWORD_PTR(20))].map { name, answer in
            "\(name) \(captionSpot(hwnd, answer) == nil ? "no" : "yes")"
        }
        print("captions \(WinWindows.className(hwnd)): \(found.joined(separator: " "))")
    }
    return 0
}
