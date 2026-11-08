import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeStash parks the front window by the stash action on a fresh choices file, then rests the
// pointer off the sliver, on it and off the slid-out window, and unstashes all. It then drags the
// window to the left edge with the Windows key held, and ends the session through the tray window's
// message. It prints the frames and the stash count after each step.
func probeStash(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let pad = WinWindows.scan(screens: screens).windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
        let hwnd = WinWindows.hwnd(pad.id)
    else {
        print("stash: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("stash: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let tray = Tray(app: app)
    print("added: \(tray.show())")
    defer { tray.hide() }
    guard let window = tray.window else {
        print("stash: no tray window")
        return 1
    }
    let stasher = app.engine.stasher
    let show = { (label: String) in print("\(label): \(app.windows.frame(pad.id).map(pixels) ?? "gone")") }
    let aim = { (x: Int32, y: Int32) in Thread { sendMouse(x, y, 0) }.start() }
    let hasItem = {
        Tray.menu(
            choices: Choices(), running: [], atLogin: false, isUltrawide: false,
            stashed: !stasher.entries.isEmpty
        ).contains { $0.command == .unstashAll }
    }
    let steps: [(wait: Double, run: () -> Void)] = [
        (
            0.5,
            {
                bringForward(hwnd)
                show("before")
                print("stash ran: \(app.engine.actions.run("stash"))")
            }
        ),
        (
            0.5,
            {
                guard let e = stasher.entries.first else {
                    print("parked: none")
                    return
                }
                show("parked")
                print("edge: \(e.s.edge.rawValue)")
                print("sliver: \(sliver(e))")
                print("shown: \(pixels(e.s.shown))")
                let away = awayPoint(e)
                aim(away.x, away.y)
            }
        ),
        (
            1.0,
            {
                show("off")
                guard let e = stasher.entries.first else { return }
                let on = sliverPoint(e)
                aim(on.x, on.y)
            }
        ),
        (
            1.0,
            {
                show("out")
                print("pointer: \(pixels(Frame(x: app.pointer.position.x, y: app.pointer.position.y, w: 0, h: 0)))")
                guard let e = stasher.entries.first else { return }
                let away = awayPoint(e)
                aim(away.x, away.y)
            }
        ),
        (
            1.0,
            {
                show("back")
                print("menu while stashed: \(hasItem())")
                print("unstash ran: \(app.engine.actions.run("unstash-all"))")
            }
        ),
        (
            0.5,
            {
                show("restored")
                print("stashed after unstash: \(stasher.entries.count)")
                print("menu after unstash: \(hasItem())")
                bringForward(hwnd)
                let from = (x: Int32((pad.frame.x + pad.frame.w / 2).rounded()), y: Int32(pad.frame.y + 15))
                Thread { dragInput(from: from, to: (x: 1, y: 400), keys: [0x5B]) }.start()
            }
        ),
        (
            3.5,
            {
                print("stashed after drag: \(stasher.entries.count)")
                if let e = stasher.entries.first {
                    print("drag edge: \(e.s.edge.rawValue)")
                    print("drag sliver: \(sliver(e))")
                }
                show("dragged")
                let front = GetForegroundWindow().map(WinWindows.className) ?? "none"
                print("foreground after the Windows key: \(front)")
                _ = SendMessageW(window, UINT(WM_ENDSESSION), 1, 0)
            }
        ),
        (
            0.5,
            {
                show("end session")
                print("stashed after end session: \(stasher.entries.count)")
            }
        ),
    ]
    let timer = app.timers.make()
    var next = 0
    func schedule() {
        guard next < steps.count else { return }
        let step = steps[next]
        next += 1
        timer.schedule(at: App.now + step.wait) {
            step.run()
            schedule()
        }
    }
    schedule()
    app.run(until: App.now + steps.reduce(0.5) { $0 + $1.wait })
    print("hook reinstalled: \(app.mouse.reinstalls)")
    return 0
}

// sliver returns how many pixels of the parked window e stay inside its area.
private func sliver(_ e: Stasher.Entry) -> Int {
    let f = e.s.hidden, a = e.area
    switch e.s.edge {
    case .left: return Int((f.x + f.w - a.x).rounded())
    case .right: return Int((a.x + a.w - f.x).rounded())
    case .bottom: return Int((a.y + a.h - f.y).rounded())
    }
}

// sliverPoint returns the middle of the sliver of the parked window e.
private func sliverPoint(_ e: Stasher.Entry) -> (x: Int32, y: Int32) {
    let f = e.s.hidden, a = e.area, half = Stash.sliver / 2
    switch e.s.edge {
    case .left: return (Int32(a.x + half), Int32(f.y + f.h / 2))
    case .right: return (Int32(a.x + a.w - half), Int32(f.y + f.h / 2))
    case .bottom: return (Int32(f.x + f.w / 2), Int32(a.y + a.h - half))
    }
}

// awayPoint returns a point at the far side of e's area from its edge, off the sliver and off the
// slid-out window.
private func awayPoint(_ e: Stasher.Entry) -> (x: Int32, y: Int32) {
    let a = e.area, margin = 20.0
    switch e.s.edge {
    case .left: return (Int32(a.x + a.w - margin), Int32(a.y + margin))
    case .right: return (Int32(a.x + margin), Int32(a.y + margin))
    case .bottom: return (Int32(a.x + a.w - margin), Int32(a.y + margin))
    }
}
