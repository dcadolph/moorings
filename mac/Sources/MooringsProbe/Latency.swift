import AppKit

// Latency times how long a window app takes to land the probe's window after one of its links asks.
// The bench runs `MooringsProbe --latency <n> <left-url> <right-url>`, a command that asks the
// running probe over a distributed notification and prints the reply, since launching a second
// probe would wake the passes a window manager runs for a newly launched app and time those.
enum Latency {
    // request asks the running probe for a run. Its userInfo carries n, left and right as strings.
    static let request = Notification.Name("com.dcadolph.moorings.probe.latency")
    // done carries the result line of a run back to the command under the line key.
    static let done = Notification.Name("com.dcadolph.moorings.probe.latency-done")
    // missAfter is how long an action may leave the window unmoved before it counts as missed.
    static let missAfter = 2.0
    // quiet is how long the window must hold still before its last move counts as the landing, so
    // an app that animates lands when its animation ends.
    static let quiet = 0.3
    // gap is the pause after each landing or miss, the same gap the bench's active phase leaves.
    static let gap = 0.25

    // line formats the landed times in milliseconds with the missed and wrong counts. A run with no
    // landing prints missed in place of both percentiles, so no reader can take it for a fast one.
    static func line(_ landed: [Double], missed: Int, wrong: Int) -> String {
        let sorted = landed.sorted()
        let p50 = rank(sorted, 0.50).map { String(format: "%.1f", $0) } ?? "missed"
        let p95 = rank(sorted, 0.95).map { String(format: "%.1f", $0) } ?? "missed"
        return "p50 \(p50) p95 \(p95) missed \(missed) wrong \(wrong) n \(landed.count + missed)"
    }

    // rank returns the nearest-rank percentile q of sorted, nil when sorted is empty.
    static func rank(_ sorted: [Double], _ q: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let i = Int((q * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(i, 0), sorted.count - 1)]
    }

    // ask sends a run of n actions to the running probe, waits for its line and returns the exit
    // code: 0 with the line printed, 1 when no reply came in time.
    @MainActor
    static func ask(n: Int, left: String, right: String) -> Int32 {
        let client = LatencyClient()
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            client, selector: #selector(LatencyClient.finished), name: done, object: nil,
            suspensionBehavior: .deliverImmediately)
        center.postNotificationName(
            request, object: nil, userInfo: ["n": String(n), "left": left, "right": right],
            deliverImmediately: true)
        let deadline = Date() + Double(n) * (missAfter + quiet + gap + 0.1) + 10
        while client.result == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date() + 0.1)
        }
        guard let result = client.result else {
            FileHandle.standardError.write(Data("probe: no latency reply from the running probe\n".utf8))
            return 1
        }
        print(result)
        return 0
    }
}

// LatencyClient holds the reply the command waits for.
@MainActor
final class LatencyClient: NSObject {
    // result is the line the probe sent back, nil until it arrives.
    private(set) var result: String?

    // finished keeps the line the done notification carries.
    @objc func finished(_ note: Notification) {
        result = note.userInfo?["line"] as? String ?? "error no line"
    }
}

// LatencyRun moves one probe window through a run of links and times each landing from the moment
// the link was opened to the last frame change before the window holds still.
@MainActor
final class LatencyRun: NSObject {
    // window is the probe window the links move.
    private let window: NSWindow
    // lastChange is the uptime in nanoseconds of the window's last move or resize, 0 before any.
    private var lastChange: UInt64 = 0

    // init watches window for moves and resizes.
    init(window: NSWindow) {
        self.window = window
        super.init()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: window)
        }
    }

    // changed notes when the window's frame last changed.
    @objc private func changed(_ note: Notification) {
        lastChange = DispatchTime.now().uptimeNanoseconds
    }

    // run opens left for odd actions and right for even ones, n in all, without bringing the target
    // app forward, the route `open -g` takes. An action that leaves the window unmoved for
    // Latency.missAfter is missed, and one that lands it on the wrong side of its screen is wrong.
    func run(_ n: Int, left: URL, right: URL) async -> String {
        var landed: [Double] = []
        var missed = 0
        var wrong = 0
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        for i in 1...n {
            let toLeft = i % 2 == 1
            lastChange = 0
            let sent = DispatchTime.now().uptimeNanoseconds
            NSWorkspace.shared.open(toLeft ? left : right, configuration: config, completionHandler: nil)
            while true {
                try? await Task.sleep(for: .milliseconds(10))
                let now = DispatchTime.now().uptimeNanoseconds
                if lastChange == 0 {
                    if Double(now - sent) / 1e9 >= Latency.missAfter {
                        missed += 1
                        break
                    }
                    continue
                }
                if Double(now - lastChange) / 1e9 >= Latency.quiet {
                    landed.append(Double(lastChange - sent) / 1e6)
                    let mid = (window.screen ?? NSScreen.main)?.visibleFrame.midX ?? 0
                    if (window.frame.midX < mid) != toLeft {
                        wrong += 1
                    }
                    break
                }
            }
            try? await Task.sleep(for: .seconds(Latency.gap))
        }
        NotificationCenter.default.removeObserver(self)
        return Latency.line(landed, missed: missed, wrong: wrong)
    }
}
