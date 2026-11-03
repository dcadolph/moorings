import AppKit

// Walk drives a scripted desk like a working day for the use measure: app switches, window moves,
// resizes and new windows. The use script runs `MooringsProbe --walk <seconds>`, a command that asks
// the running probe over a distributed notification and prints its reply, for the same reason the
// latency mode does. The walk posts no input events, so it needs no Accessibility access.
enum Walk {
    // request asks the running probe for a walk. Its userInfo carries seconds and other, the bundle
    // id of the app each switch goes to and back from.
    static let request = Notification.Name("com.dcadolph.moorings.probe.walk")
    // done carries the walk's count line back to the command under the line key.
    static let done = Notification.Name("com.dcadolph.moorings.probe.walk-done")
    // switchEvery is the seconds between app switches.
    static let switchEvery = 2
    // moveEvery is the seconds between window moves.
    static let moveEvery = 5
    // resizeEvery is the seconds between window resizes.
    static let resizeEvery = 7
    // windowEvery is the seconds between new windows.
    static let windowEvery = 11
    // reach is how far a move goes, in points, before it comes back.
    static let reach: CGFloat = 300
    // grow is how much a resize widens the window, in points, before it comes back.
    static let grow: CGFloat = 100
    // steps is how many frames a move or resize takes each way.
    static let steps = 20
    // stepGap is the time between those frames.
    static let stepGap = Duration.milliseconds(20)

    // ask sends a walk of seconds to the running probe, waits for its line and returns the exit
    // code: 0 with the line printed, 1 when no reply came in time.
    @MainActor
    static func ask(seconds: Int, other: String) -> Int32 {
        let client = ReplyClient()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            client, selector: #selector(ReplyClient.finished), name: done, object: nil,
            suspensionBehavior: .deliverImmediately)
        center.postNotificationName(
            request, object: nil, userInfo: ["seconds": String(seconds), "other": other], deliverImmediately: true)
        let deadline = Date() + Double(seconds) + 30
        while client.result == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date() + 0.1)
        }
        guard let result = client.result else {
            FileHandle.standardError.write(Data("probe: no walk reply from the running probe\n".utf8))
            return 1
        }
        print(result)
        return 0
    }
}

// WalkRun runs one walk on a probe window and counts what it did.
@MainActor
final class WalkRun {
    // window is the probe window the walk moves and resizes.
    private let window: NSWindow
    // other is the app each switch brings forward before the probe comes back.
    private let other: URL
    // newWindow opens a second probe window and returns it.
    private let newWindow: () -> NSWindow

    // init walks window, switching to the app at other and opening windows through newWindow.
    init(window: NSWindow, other: URL, newWindow: @escaping () -> NSWindow) {
        self.window = window
        self.other = other
        self.newWindow = newWindow
    }

    // run walks for seconds, firing each kind of event on its own period from the start, and returns
    // the count line. Both sides of a switch go through Launch Services, as a Dock click does, since
    // an app in the background may not take activation back by itself.
    func run(seconds: Int) async -> String {
        var switches = 0
        var moves = 0
        var resizes = 0
        var windows = 0
        let start = ContinuousClock.now
        for s in 1...seconds {
            try? await Task.sleep(until: start + .seconds(s), clock: .continuous)
            if s % Walk.switchEvery == 0 {
                await activate(other)
                try? await Task.sleep(for: .milliseconds(300))
                await activate(Bundle.main.bundleURL)
                switches += 1
            }
            if s % Walk.moveEvery == 0 {
                await step(dx: Walk.reach, dw: 0)
                moves += 1
            }
            if s % Walk.resizeEvery == 0 {
                await step(dx: 0, dw: Walk.grow)
                resizes += 1
            }
            if s % Walk.windowEvery == 0 {
                let w = newWindow()
                try? await Task.sleep(for: .seconds(1))
                w.close()
                window.makeKeyAndOrderFront(nil)
                windows += 1
            }
        }
        return "walk seconds \(seconds) switches \(switches) moves \(moves) resizes \(resizes) windows \(windows)"
    }

    // activate brings the app at url forward through Launch Services.
    private func activate(_ url: URL) async {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // step moves the window right by dx and widens it by dw over Walk.steps frames, then brings it
    // back the same way, so every frame reaches the window's observers as a move or a resize.
    private func step(dx: CGFloat, dw: CGFloat) async {
        let base = window.frame
        for leg in [1.0, -1.0] {
            for i in 1...Walk.steps {
                let k = leg > 0 ? CGFloat(i) / CGFloat(Walk.steps) : 1 - CGFloat(i) / CGFloat(Walk.steps)
                var f = base
                f.origin.x += dx * k
                f.size.width += dw * k
                window.setFrame(f, display: true)
                try? await Task.sleep(for: Walk.stepGap)
            }
        }
    }
}
