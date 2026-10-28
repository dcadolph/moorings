import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probePlace moves the front Notepad window twice and prints each read-back and its insets.
func probePlace(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("place: no window of \(opts.app)")
        return 1
    }
    let placer = WinWindows()
    placer.corrects = !opts.noDelta
    let targets =
        opts.frame.map { [$0] }
        ?? [Frame(x: 100, y: 100, w: 800, h: 600), Frame(x: 300, y: 200, w: 640, h: 480)]
    for target in targets {
        placer.move(pad.id, to: target)
        print("asked: \(pixels(target)) placed: \(placer.frame(pad.id).map(pixels) ?? "gone")")
    }
    let d = WinWindows.hwnd(pad.id).flatMap(WinWindows.insets) ?? Insets()
    print(
        "delta: \(Int(d.left)) \(Int(d.top)) \(Int(d.right)) \(Int(d.bottom))",
        "elevated \(placer.elevated.contains(pad.id))")
    return 0
}
