import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeTray adds the tray icon, chooses the front Notepad for the left top slot and then Pause
// through the menu's commands, prints the saved choices after each, and removes the icon.
func probeTray(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("tray: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("tray: \(error)")
        return 1
    }
    let tray = Tray(app: App(store: store, minAspect: opts.minAspect))
    print("icon: \(Tray.loadIcon() == nil ? "none" : "loaded")")
    print("added: \(tray.show())")
    tray.perform(.slot(.leftTop, pad.bundle))
    print("saved left top: \(store.load().slots[.leftTop] ?? "")")
    tray.perform(.pause)
    print("saved paused: \(store.load().paused)")
    tray.hide()
    return 0
}
