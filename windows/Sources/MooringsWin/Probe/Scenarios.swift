import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeScenarios runs the shared scenarios named after --scenarios, every one when none is named, on
// the Win32 adapters against stand-in windows from this exe's stand probe. It writes report.json,
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
    app.notify = { title, body in print("notice: \(title): \(body)") }
    let host = WinHost(minAspect: opts.minAspect)
    host.timers = { app.timers.fire($0) }
    host.hotkey = { app.hotkeys.fire($0) }
    host.shots = dir
    let results = Scenarios.run(app.engine, host: host, only: only, skew: opts.skew)
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
