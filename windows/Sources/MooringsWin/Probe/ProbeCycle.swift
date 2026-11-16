import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// cycleText is the line the cycle probe's Edit control holds, so a word move from its start lands at
// 6, the start of "beta".
let cycleText = "alpha beta gamma"

// cycleSteps are the cycle probe's caret steps: each brings the fill forward, then the Edit stand-in,
// and presses Control-Right that many milliseconds after the switch.
let cycleSteps: [(label: String, wait: DWORD)] = [("fast", 50), ("slow", 500)]

// probeCycle proves the channel cycle's claim on Windows from a fresh choices file. It opens a stand-in
// with an Edit control in its own process, then three stand-ins in the channel, fills the channel with
// the first and prints whether the keys are claimed. While the loop runs, a second thread presses
// Control-Right and Control-Left and prints the window in front after each, then for each step brings
// the Edit stand-in back where it opened, since the walk may have filled the channel with it, brings
// the fill forward, brings the Edit stand-in forward, presses Control-Right after the step's wait and
// prints where the caret landed. Under --cycle-hold the claim stays through the focus change until the
// next pass, the control, so the fast press is swallowed.
func probeCycle(_ opts: ProbeOptions) -> Int32 {
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-cycle-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: Store(url: file).aside)
    }
    let store = Store(url: file)
    do {
        try store.save(Choices())
    } catch {
        print("cycle: \(error)")
        return 1
    }
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let i = screens.host else {
        print("cycle: no host display at min aspect \(opts.minAspect)")
        return 1
    }
    guard let stand = openEditStand() else { return 1 }
    defer { stand.process.terminate() }
    let app = App(store: store, minAspect: opts.minAspect)
    app.engine.channelCycle.letsGoOnFocus = !opts.cycleHold
    let host = WinHost(minAspect: opts.minAspect)
    host.timers = { app.timers.fire($0) || app.mouse.tick($0) }
    defer { host.finish() }
    print("hold: \(opts.cycleHold)")
    print("edit stand-in: \(hex(WinWindows.id(stand.top)))")
    let c = app.engine.organizer.area(screens, i)
    var pads: [WindowID] = []
    for k in 0..<3 {
        guard let id = host.open() else {
            print("cycle: stand-in \(k) did not open")
            return 1
        }
        let f = Frame(x: c.x + 100 + 40 * Double(k), y: c.y + 100, w: 700, h: 500)
        app.windows.move(id, to: f, from: nil, behavior: Behaviors())
        pads.append(id)
    }
    print("pads: \(pads.map(hex).joined(separator: " "))")
    app.windows.raise(pads[0])
    app.run(until: App.now + 0.5)
    let now = Screens.current(minAspect: opts.minAspect)
    guard let first = app.windows.scan(now, full: true).windows.first(where: { $0.id == pads[0] }),
        app.engine.actions.fill(first, screens: now)
    else {
        print("cycle: the first stand-in did not fill the channel")
        return 1
    }
    app.run(until: App.now + 1)
    print("claimed: \(app.engine.channelCycle.claimed) keys \(app.hotkeys.claimedKeys)")
    print("front: \(foreground())")
    let loop = GetCurrentThreadId()
    let topBits = UInt(bitPattern: stand.top), editBits = UInt(bitPattern: stand.edit)
    let fill = pads[0]
    var opened = RECT()
    _ = GetWindowRect(stand.top, &opened)
    let home = (x: opened.left, y: opened.top, w: opened.right - opened.left, h: opened.bottom - opened.top)
    print("edit home: \(home.x) \(home.y) \(home.w) \(home.h)")
    Thread {
        Sleep(500)
        for (label, vk) in [("right", WORD(0x27)), ("left", WORD(0x25))] {
            print("\(label) sent: \(press([0x11, vk]))")
            Sleep(800)
            print("\(label) front: \(foreground())")
        }
        guard let top = HWND(bitPattern: topBits), let edit = HWND(bitPattern: editBits),
            let filled = WinWindows.hwnd(fill)
        else {
            print("cycle: a stand-in is gone")
            _ = PostThreadMessageW(loop, UINT(WM_QUIT), 0, 0)
            return
        }
        for step in cycleSteps {
            // 0x0014 is SWP_NOZORDER and SWP_NOACTIVATE.
            _ = SetWindowPos(top, nil, home.x, home.y, home.w, home.h, 0x0014)
            print("\(step.label) fill forward: \(bringForward(filled))")
            Sleep(800)
            resetEdit(edit)
            print("\(step.label) edit forward: \(bringForward(top))")
            Sleep(step.wait)
            print("\(step.label) sent: \(press([0x11, 0x27]))")
            Sleep(300)
            print("\(step.label) caret: \(caret(edit))")
            print("\(step.label) front: \(foreground())")
        }
        _ = PostThreadMessageW(loop, UINT(WM_QUIT), 0, 0)
    }.start()
    app.run(until: App.now + 10)
    let pressed = app.hotkeys.pressed
    print("hotkeys received: \(pressed.isEmpty ? "none" : pressed.joined(separator: ","))")
    return 0
}

// openEditStand starts the stand probe with an Edit control in its own process, since the window
// events skip the app's own windows, and returns the process, its window and its Edit once it shows.
private func openEditStand() -> (process: Process, top: HWND, edit: HWND)? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: LoginItem.executable)
    p.arguments = ["--probe", "stand", "--edit", "--seconds", "120"]
    do {
        try p.run()
    } catch {
        print("cycle: edit stand-in did not start: \(error)")
        return nil
    }
    let pid = DWORD(p.processIdentifier)
    let until = App.now + 5
    while App.now < until {
        let top = WinWindows.topLevel().first {
            WinWindows.processID($0) == pid && WinWindows.className($0) == standClass && IsWindowVisible($0)
        }
        if let top, let edit = FindWindowExW(top, nil, wide("Edit"), nil) {
            return (p, top, edit)
        }
        Sleep(50)
    }
    print("cycle: edit stand-in showed no window")
    p.terminate()
    return nil
}

// resetEdit puts cycleText in edit with the caret at its start.
private func resetEdit(_ edit: HWND) {
    var text = wide(cycleText)
    _ = text.withUnsafeMutableBufferPointer { buffer in
        SendMessageW(edit, UINT(WM_SETTEXT), 0, LPARAM(Int(bitPattern: buffer.baseAddress)))
    }
    // 0x00B1 is EM_SETSEL.
    _ = SendMessageW(edit, 0x00B1, 0, 0)
}

// caret returns where edit's caret sits, the end of its selection.
private func caret(_ edit: HWND) -> Int {
    // 0x00B0 is EM_GETSEL, which packs the start in the low word and the end in the high word.
    let sel = SendMessageW(edit, 0x00B0, 0, 0)
    return Int((UInt(bitPattern: Int(sel)) >> 16) & 0xFFFF)
}
