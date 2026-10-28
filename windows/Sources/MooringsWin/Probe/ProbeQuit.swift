import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeQuit adds the tray icon and runs the loop for two seconds to show it does not end by itself,
// then chooses Quit through the tray's command, runs the loop again with five seconds to spare, and
// prints how long each run took and whether the icon is gone after the tray hides.
func probeQuit(_: ProbeOptions) -> Int32 {
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("quit: \(error)")
        return 1
    }
    let app = App(store: store)
    let tray = Tray(app: app)
    print("added: \(tray.show())")
    var t = App.now
    app.run(until: t + 2)
    print("ran without quit: \(stamp(App.now - t)) s")
    tray.perform(.quit)
    t = App.now
    app.run(until: t + 5)
    print("ran after quit: \(stamp(App.now - t)) s")
    let window = tray.window
    tray.hide()
    print("icon gone: \(window.map(Tray.iconGone) ?? false)")
    return 0
}
