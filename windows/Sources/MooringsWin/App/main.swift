import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// A link or --action is read before anything else, and a link ignores every argument after it.
let arguments = Array(CommandLine.arguments.dropFirst())
let request = LinkRequest(arguments)

// The streams open before anything can write. --no-streams skips it, the console probe's negative
// control, and is read here because a bad command line already writes to stderr.
if request != nil || !arguments.contains("--no-streams") {
    openStandardStreams()
}

// Per-Monitor-V2 must be set before any window call, so frames come back in physical pixels.
_ = SetProcessDpiAwarenessContext(perMonitorAwareV2)

let linked = request.map(Links.deliver)

let options: ProbeOptions
do {
    options = try ProbeOptions(request == nil ? arguments : [])
} catch {
    FileHandle.standardError.write(Data("MooringsWin: \(error)\n".utf8))
    exit(2)
}
Monitor.fake = options.screen.map { Monitor.sized($0, scale: options.scale) }

guard let name = options.probe else {
    if linked == nil, let window = Links.running() {
        _ = PostMessageW(window, Tray.again, 0, 0)
        exit(0)
    }
    let app = App(store: Store(), minAspect: options.minAspect)
    if let linked {
        let answer = Links.answer(app.engine.actions.linkVerdict(linked))
        if answer != Links.ran {
            app.log.note(.actions, "a moorings link asked for \(linked): Moorings did not start")
            exit(Links.say(answer, linked))
        }
    }
    Links.register(app.log)
    let banner = BannerWindow()
    app.notify = { banner.show($0, $1) }
    let tray = Tray(app: app)
    tray.show()
    tray.watchUpdates()
    app.engine.start()
    if let linked {
        _ = tray.answer(linked)
    }
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
