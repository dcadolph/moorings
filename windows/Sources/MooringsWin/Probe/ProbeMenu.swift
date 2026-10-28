import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeMenu prints the tray menu the saved choices and the running windows build, one entry per
// line, indented by depth, with [x] beside a checked entry.
func probeMenu(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let running = opts.noApps ? [] : WinWindows.scan(screens: screens).windows.map(\.bundle)
    printMenu(Tray.menu(choices: Store().load().choices, running: running, atLogin: LoginItem.enabled))
    return 0
}

// printMenu prints items and their folders, depth levels in.
func printMenu(_ items: [MenuItem], depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    for item in items {
        guard !item.title.isEmpty else {
            print("menu \(indent)-")
            continue
        }
        print("menu \(indent)[\(item.checked ? "x" : " ")] \(item.title)\(item.enabled ? "" : " (off)")")
        printMenu(item.submenu, depth: depth + 1)
    }
}
