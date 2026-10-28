import Foundation
import WinSDK

import MooringsCore

// Per-Monitor-V2 must be set before any window call, so frames come back in physical pixels.
_ = SetProcessDpiAwarenessContext(perMonitorAwareV2)

let options: ProbeOptions
do {
    options = try ProbeOptions(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("MooringsWin: \(error)\n".utf8))
    exit(2)
}
Monitor.fake = options.screen.map(Monitor.sized)

guard let name = options.probe else {
    let app = App(store: Store())
    let banner = BannerWindow()
    app.notify = { banner.show($0, $1) }
    app.hotkeys.bind(Bindings(app.anchors.choices).map, runnable: app.actions.supports)
    let tray = Tray(app: app)
    tray.show()
    app.anchors.launch(now: App.now)
    app.run()
    tray.hide()
    app.hotkeys.unbind()
    exit(0)
}
guard let probe = probes[name] else {
    FileHandle.standardError.write(Data("MooringsWin: unknown probe \(name)\n".utf8))
    exit(2)
}
exit(probe(options))
