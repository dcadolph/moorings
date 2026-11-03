import AppKit

// Drags posts real mouse drags for the second part of the use measure: a title bar drag of a probe
// window and a text selection drag inside it, the two drags every window manager that follows drags
// sees most in a working day. The use script runs `MooringsProbe --drags <seconds>`, a command that
// asks the running probe over a distributed notification and prints its reply, as the walk does.
// Posting input events needs the probe trusted for Accessibility, so an untrusted probe asks for it
// with the system prompt and the reply says it is not trusted.
enum Drags {
    // request asks the running probe for a drag run. Its userInfo carries seconds.
    static let request = Notification.Name("com.dcadolph.moorings.probe.drags")
    // done carries the run's count line back to the command under the line key.
    static let done = Notification.Name("com.dcadolph.moorings.probe.drags-done")
    // every is the seconds between the starts of a title bar drag, each followed by a selection drag.
    static let every = 3
    // reach is how far a title bar drag goes, in points, before it comes back to where it began.
    static let reach: CGFloat = 300
    // steps is how many dragged events a drag posts each way.
    static let steps = 20
    // stepGap is the time between those events.
    static let stepGap = Duration.milliseconds(20)
    // size is the drag window's frame size.
    static let size = NSSize(width: 600, height: 400)

    // ask sends a drag run of seconds to the running probe, waits for its line and returns the exit
    // code: 0 with the line printed, 1 when no reply came in time.
    @MainActor
    static func ask(seconds: Int) -> Int32 {
        let client = ReplyClient()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            client, selector: #selector(ReplyClient.finished), name: done, object: nil,
            suspensionBehavior: .deliverImmediately)
        center.postNotificationName(
            request, object: nil, userInfo: ["seconds": String(seconds)], deliverImmediately: true)
        let deadline = Date() + Double(seconds) + 30
        while client.result == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date() + 0.1)
        }
        guard let result = client.result else {
            FileHandle.standardError.write(Data("probe: no drags reply from the running probe\n".utf8))
            return 1
        }
        print(result)
        return 0
    }
}

// DragRun opens a window with text in it, drags it by its title bar and selects its text with real
// mouse events, and counts what it did.
@MainActor
final class DragRun {
    // window is the window the run drags, closed when the run ends.
    private let window: NSWindow
    // text is the text view the selection drags run across.
    private let text: NSTextView

    // init opens the drag window centered on the main screen, filled with lines of text.
    init() {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Drags.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.title = "Probe drags"
        let scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as! NSTextView
        text.string = (1...40).map { "Line \($0) of the text a selection drag runs across." }.joined(separator: "\n")
        window.contentView = scroll
        window.center()
    }

    // run drags for seconds, a title bar drag at the start of each period and a selection drag half a
    // period later, puts the pointer back where it was and returns the count line. An untrusted probe
    // shows the system prompt that opens the Accessibility settings and drags nothing.
    func run(seconds: Int) async -> String {
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else {
            window.close()
            return "error not trusted for Accessibility"
        }
        let home = CGEvent(source: nil)?.location
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try? await Task.sleep(for: .seconds(1))
        var bars = 0
        var selections = 0
        let start = ContinuousClock.now
        var s = 0
        while s + Drags.every <= seconds {
            try? await Task.sleep(until: start + .seconds(s), clock: .continuous)
            let f = Self.top(window.frame)
            let bar = CGPoint(x: f.midX, y: f.minY + 12)
            await drag(from: bar, by: CGVector(dx: Drags.reach, dy: 0), back: true)
            bars += 1
            try? await Task.sleep(until: start + .seconds(s) + .milliseconds(Drags.every * 500), clock: .continuous)
            let g = Self.top(window.frame)
            let inside = CGPoint(x: g.minX + 40, y: g.minY + 60)
            await drag(from: inside, by: CGVector(dx: 300, dy: 80), back: false)
            selections += 1
            s += Drags.every
        }
        window.close()
        if let home {
            CGWarpMouseCursorPosition(home)
        }
        return "drags seconds \(seconds) title bar \(bars) selections \(selections)"
    }

    // drag presses at p, posts Drags.steps dragged events toward p plus by, then the same back to p
    // when back is set, and releases where it stopped.
    private func drag(from p: CGPoint, by v: CGVector, back: Bool) async {
        post(.leftMouseDown, at: p)
        try? await Task.sleep(for: Drags.stepGap)
        var at = p
        for leg in back ? [1.0, -1.0] : [1.0] {
            for i in 1...Drags.steps {
                let k = leg > 0 ? CGFloat(i) / CGFloat(Drags.steps) : 1 - CGFloat(i) / CGFloat(Drags.steps)
                at = CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k)
                post(.leftMouseDragged, at: at)
                try? await Task.sleep(for: Drags.stepGap)
            }
        }
        post(.leftMouseUp, at: at)
        try? await Task.sleep(for: Drags.stepGap)
    }

    // post sends one left button event of type at p, in global top-left coordinates, through the HID
    // tap, as a mouse does.
    private func post(_ type: CGEventType, at p: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // top turns an AppKit frame, bottom-left on the primary screen, into global top-left coordinates.
    private static func top(_ f: NSRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height)
    }
}
