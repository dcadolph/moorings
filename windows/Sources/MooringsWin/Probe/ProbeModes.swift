import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeModes prints every display mode of the primary adapter, the current one, the largest one at
// least minAspect wide, and the largest window size Windows allows. With --mode it switches to a
// mode until the next switch, and with --reset it restores the mode kept in the registry.
func probeModes(_ opts: ProbeOptions) -> Int32 {
    if opts.reset {
        let r = ChangeDisplaySettingsExW(nil, nil, nil, 0, nil)
        print("reset: \(r == 0 ? "done" : "failed \(r)")")
        return r == 0 ? 0 : 1
    }
    if let mode = opts.mode {
        var dm = DEVMODEW()
        dm.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
        dm.dmPelsWidth = DWORD(mode.w)
        dm.dmPelsHeight = DWORD(mode.h)
        dm.dmFields = DWORD(DM_PELSWIDTH | DM_PELSHEIGHT)
        let r = ChangeDisplaySettingsExW(nil, &dm, nil, 0, nil)
        print("switched to \(mode.w)x\(mode.h): \(r == 0 ? "done" : "failed \(r)")")
        return r == 0 ? 0 : 1
    }
    var dm = DEVMODEW()
    dm.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
    var sizes: [Size] = []
    var i: DWORD = 0
    while EnumDisplaySettingsW(nil, i, &dm) {
        let size = Size(w: Int(dm.dmPelsWidth), h: Int(dm.dmPelsHeight))
        if !sizes.contains(size) {
            sizes.append(size)
        }
        i += 1
    }
    sizes.sort { ($0.w, $0.h) < ($1.w, $1.h) }
    for s in sizes {
        print("mode \(s.w)x\(s.h) aspect \(String(format: "%.2f", Double(s.w) / Double(s.h)))")
    }
    if EnumDisplaySettingsW(nil, DWORD.max, &dm) {
        print("current: \(dm.dmPelsWidth)x\(dm.dmPelsHeight)")
    }
    let wide = sizes.filter { Double($0.w) / Double($0.h) >= opts.minAspect }.max { $0.w * $0.h < $1.w * $1.h }
    print("ultrawide mode: \(wide.map { "\($0.w)x\($0.h)" } ?? "none")")
    print("max track: \(GetSystemMetrics(SM_CXMAXTRACK)) \(GetSystemMetrics(SM_CYMAXTRACK))")
    return sizes.isEmpty ? 1 : 0
}
