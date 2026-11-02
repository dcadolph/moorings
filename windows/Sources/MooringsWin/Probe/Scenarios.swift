import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeScenarios runs the shared scenarios named after --scenarios, every one when none is named, on
// the Win32 adapters against stand-in windows from this exe's stand probe or the browser --stand-in
// names, with the mouse hook feeding drags to the engine as the app's loop does. Under --no-delta the
// engine places without the border correction, the negative control. It writes report.json,
// report.html and one PNG per scenario into the report folder, prints each number, frame and broken
// rule, and ends with the summary line the workflow checks.
func probeScenarios(_ opts: ProbeOptions) -> Int32 {
    let only = Set(opts.scenarios)
    let unknown = Scenarios.unknown(only)
    guard unknown.isEmpty else {
        print("scenarios: no scenario named \(unknown.joined(separator: " "))")
        return 2
    }
    let dir = URL(fileURLWithPath: opts.report)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        print("scenarios: no report folder: \(error)")
        return 1
    }
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-scenarios-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: Store(url: file).aside)
    }
    let app = App(store: Store(url: file), minAspect: opts.minAspect)
    app.windows.corrects = !opts.noDelta
    WinDrag.verbose = true
    app.notify = { title, body in print("notice: \(title): \(body)") }
    let host = WinHost(minAspect: opts.minAspect)
    host.timers = { app.timers.fire($0) || app.mouse.tick($0) }
    host.hotkey = { app.hotkeys.fire($0) }
    host.mouse = { app.mouse.deliver($0) }
    host.shots = dir
    host.choices = file
    host.standIn = opts.standIn
    if opts.standIn != nil {
        host.measureStandIn()
    }
    app.mouse.handler = { message, p in
        if message == UINT(WM_MOUSEMOVE) {
            app.drag.pointer(p)
        }
    }
    app.mouse.start()
    let results = Scenarios.run(app.engine, host: host, only: only, skew: opts.skew)
    app.mouse.stop()
    print("hook reinstalled: \(app.mouse.reinstalls)")
    app.hotkeys.unbind()
    let report = ScenarioReport(host: "windows", results: results)
    for r in results {
        if let why = r.skipped {
            print("scenario \(r.name): skipped, \(why)")
        }
        for f in r.frames {
            print("scenario \(r.name) frame \(f.name): \(Int(f.x)) \(Int(f.y)) \(Int(f.w)) \(Int(f.h))")
        }
        for n in r.notes {
            print("scenario \(r.name): \(n)")
        }
    }
    for f in report.failures {
        print("scenario failed: \(f)")
    }
    do {
        try report.write(to: dir)
    } catch {
        print("scenarios: report not written: \(error)")
        return 1
    }
    print(report.summary)
    return report.failures.isEmpty ? 0 : 1
}

extension WinHost: ScenarioHost {
    // place moves the window with id to frame from outside the engine's store, with the border
    // correction the nudge probe uses, and reports whether the window was there to move.
    func place(_ id: WindowID, at frame: Frame) -> Bool {
        guard WinWindows.hwnd(id) != nil else { return false }
        WinWindows().move(id, to: frame)
        return true
    }

    // grabRow is how far below the frame's top the grab walks for a caption, Scenarios.grab's row.
    static let grabRow = 15.0
    // grabStep is how far apart the walk hit-tests the row.
    static let grabStep = 4
    // grabRun is the narrowest run of caption answers the walk takes as a grab.
    static let grabRun = 12

    // grab returns where a person would press to drag the window with id and frame f by its title
    // bar. It brings the window forward, since the press lands on the front window, and hit-tests
    // Scenarios.grab of f: when the window answers HTCAPTION there, that is the grab. Otherwise it walks
    // the same row from the right edge to the left in grabStep px steps and returns the middle of the
    // longest run of HTCAPTION answers at least grabRun px wide, nil when the row has none. A hit test
    // that times out counts as not caption. It prints one grab line per call.
    func grab(_ id: WindowID, frame f: Frame) -> Point? {
        guard let hwnd = WinWindows.hwnd(id) else { return nil }
        _ = bringForward(hwnd)
        func hit(_ x: Int32, _ y: Int32) -> DWORD_PTR? {
            WinDrag.hit(hwnd, at: POINT(x: x, y: y))
        }
        func name(_ answer: DWORD_PTR?) -> String {
            answer.map { "\($0)" } ?? "none"
        }
        let fallback = Scenarios.grab(f)
        let dx = Int32(fallback.x.rounded()), dy = Int32(fallback.y.rounded())
        let first = hit(dx, dy)
        let head = "grab: default \(dx) \(dy) hit \(name(first))"
        if first == WinDrag.caption {
            print("\(head), chosen \(dx) \(dy) hit 2, at the default")
            return fallback
        }
        let y = Int32((f.y + Self.grabRow).rounded())
        let right = Int32((f.x + f.w).rounded()) - 1, left = Int32(f.x.rounded()) + 1
        // runs holds each maximal run of equal answers along the row, right to left, with the x of its
        // first and last sample.
        var runs: [(answer: DWORD_PTR?, high: Int32, low: Int32, count: Int)] = []
        for x in stride(from: right, through: left, by: -Self.grabStep) {
            let answer = hit(x, y)
            if let last = runs.last, last.answer == answer {
                runs[runs.count - 1].low = x
                runs[runs.count - 1].count += 1
            } else {
                runs.append((answer, x, x, 1))
            }
        }
        let best = runs.filter { $0.answer == WinDrag.caption && $0.count * Self.grabStep >= Self.grabRun }
            .max { $0.count < $1.count }
        guard let best else {
            let row = runs.map { "\(name($0.answer))x\($0.count * Self.grabStep)" }.joined(separator: " ")
            print("\(head), no caption on the row y \(y): \(row)")
            return nil
        }
        let cx = (best.high + best.low) / 2
        print("\(head), chosen \(cx) \(y) hit 2, run \(best.count * Self.grabStep) px")
        return Point(x: Double(cx), y: Double(y))
    }

    // drag brings the window forward, then from another thread presses on it at from with SendInput,
    // holds the keys in held, moves the pointer to to in 20 steps and lets go, while this thread pumps
    // the messages the mouse hook and the window events arrive by, then prints what the press saw.
    // It reports whether the window was there and the input finished within 5 s.
    func drag(_ id: WindowID, from: Point, to: Point, held: Modifiers) -> Bool {
        guard let hwnd = WinWindows.hwnd(id) else { return false }
        _ = bringForward(hwnd)
        let start = (x: Int32(from.x.rounded()), y: Int32(from.y.rounded()))
        let end = (x: Int32(to.x.rounded()), y: Int32(to.y.rounded()))
        let keys = Self.modifierKeys.filter { held.contains($0.0) }.map(\.1)
        let done = InputDone()
        let seen = WinMouseHook.delivered
        Thread {
            Sleep(200)
            dragInput(from: start, to: end, keys: keys)
            done.finish()
        }.start()
        let finished = wait(until: now + 5) { done.finished }
        describeInput(WinMouseHook.delivered &- seen, at: POINT(x: start.x, y: start.y))
        return finished
    }

    // describeInput prints what a scripted drag's press saw: the messages the hook delivered over
    // the drag, the press the loop thread classified, the foreground window, and the top-level
    // window under the grab point p with its hit test there, so a drag that never started says why.
    func describeInput(_ delivered: Int, at p: POINT) {
        let last = WinDrag.lastPress
        let press = last.map { "\($0.x) \($0.y)" } ?? "none"
        let age = last.map { "\(GetTickCount64() &- $0.tick)" } ?? "none"
        let root = last?.root.map(WinWindows.className) ?? "none"
        let answer = last?.answer.map { "\($0)" } ?? "none"
        let front = GetForegroundWindow().map(WinWindows.className) ?? "none"
        let under = WindowFromPoint(p).flatMap { GetAncestor($0, WinWatcher.root) }
        let hit = under.flatMap { WinDrag.hit($0, at: p) }.map { "\($0)" } ?? "none"
        print(
            "drag: input delivered \(delivered) press \(press) age \(age) ms root \(root) hit \(answer)",
            "foreground \(front) under \(under.map(WinWindows.className) ?? "none") hit \(hit)")
    }

    // shot copies the virtual desktop with GDI into name.png in the report folder and returns the
    // file's name, nil when there is no folder or the copy failed. A picture with every pixel black
    // prints a line, since a headless desktop can give one.
    func shot(_ name: String) -> String? {
        guard let shots, let picture = desktopPixels() else { return nil }
        if !picture.pixels.enumerated().contains(where: { $0.offset % 4 != 3 && $0.element != 0 }) {
            print("scenarios: the picture for \(name) is black")
        }
        let file = "\(name).png"
        let data = PNG.encode(width: picture.w, height: picture.h, pixels: picture.pixels, red: 2, blue: 0)
        guard (try? data.write(to: shots.appendingPathComponent(file))) != nil else { return nil }
        return file
    }
}

// InputDone tells the loop thread that the input thread finished.
final class InputDone: @unchecked Sendable {
    // lock guards done.
    private let lock = NSLock()
    // done is whether the input thread finished.
    private var done = false

    // finish marks the input thread finished.
    func finish() {
        lock.lock()
        done = true
        lock.unlock()
    }

    // finished reports whether the input thread finished.
    var finished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }
}

// desktopPixels copies the virtual desktop into 4 bytes a pixel, blue first, top row first.
func desktopPixels() -> (w: Int, h: Int, pixels: [UInt8])? {
    let x = GetSystemMetrics(SM_XVIRTUALSCREEN), y = GetSystemMetrics(SM_YVIRTUALSCREEN)
    let w = GetSystemMetrics(SM_CXVIRTUALSCREEN), h = GetSystemMetrics(SM_CYVIRTUALSCREEN)
    guard w > 0, h > 0, let screen = GetDC(nil) else { return nil }
    defer { _ = ReleaseDC(nil, screen) }
    guard let memory = CreateCompatibleDC(screen) else { return nil }
    defer { _ = DeleteDC(memory) }
    guard let bitmap = CreateCompatibleBitmap(screen, w, h) else { return nil }
    defer { _ = DeleteObject(UnsafeMutableRawPointer(bitmap)) }
    let old = SelectObject(memory, UnsafeMutableRawPointer(bitmap))
    // 0x00CC0020 is SRCCOPY and 0x40000000 is CAPTUREBLT, which takes layered windows too.
    let copied = BitBlt(memory, 0, 0, w, h, screen, x, y, DWORD(0x00CC_0020 | 0x4000_0000))
    _ = SelectObject(memory, old)
    guard copied else { return nil }
    var info = BITMAPINFO()
    info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
    info.bmiHeader.biWidth = w
    info.bmiHeader.biHeight = -h
    info.bmiHeader.biPlanes = 1
    info.bmiHeader.biBitCount = 32
    info.bmiHeader.biCompression = 0
    var pixels = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
    let rows = pixels.withUnsafeMutableBytes {
        GetDIBits(memory, bitmap, 0, UINT(h), $0.baseAddress, &info, 0)
    }
    guard rows == h else { return nil }
    return (Int(w), Int(h), pixels)
}
