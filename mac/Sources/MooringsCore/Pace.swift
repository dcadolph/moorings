// Pace decides when the next pass runs: every pollSeconds while windows change, every busySeconds
// while something is pending that sends no event, at the next deadline once windows settle, and not
// at all when nothing is due, until an event wakes it.
public enum Pace {
    // pollSeconds is the gap between passes while windows change.
    public static let pollSeconds = 0.25
    // settleSeconds is how long after the last event passes keep running every pollSeconds.
    public static let settleSeconds = 2.0
    // busySeconds is the gap between passes while something is pending that sends no event.
    public static let busySeconds = 2.0
    // slack is how long after a deadline its pass runs, so the decision has changed by then.
    static let slack = 0.05

    // next returns when the pass after one at now runs, given the last event at woke, whether
    // something pending needs a look without an event, the times a pass decides differently, and
    // whether the pass read the same windows as the one before and moved none, which ends the
    // settle window early. Deadlines at or before now are spent. It returns nil when no pass is due
    // until an event.
    public static func next(now: Double, woke: Double, busy: Bool, deadlines: [Double], still: Bool = false) -> Double? {
        if !still && now - woke < settleSeconds {
            return now + pollSeconds
        }
        var at: Double? = busy ? now + busySeconds : nil
        for d in deadlines where d > now {
            at = min(at ?? .infinity, d + slack)
        }
        return at
    }

    // geometryEvents lists the window notifications that report a window's place or birth.
    static let geometryEvents: Set<String> = ["AXWindowMoved", "AXWindowResized", "AXWindowCreated"]

    // wakes reports whether a window event named note asks for a pass, given whether the last scan
    // kept the window and whether a scan would keep it. A move, resize or birth of a window no scan
    // keeps, such as a browser's previews and popovers, changes nothing a pass decides.
    public static func wakes(_ note: String, kept: Bool, eligible: Bool) -> Bool {
        !geometryEvents.contains(note) || kept || eligible
    }
}

extension Anchors {
    // deadlines returns the times after the last pass at which a pass decides differently with no
    // window event in between: an opened app's strip lapsing, a hold on a fighting window ending,
    // and a fullscreen window's next request to leave.
    public func deadlines() -> [Double] {
        var out: [Double] = []
        for (bundle, at) in openedAt where present?.contains(bundle) != true {
            out.append(at + Self.openSeconds)
        }
        out += bursts.values.compactMap(\.holdUntil)
        out += pendingFill.values.map { $0 + Self.pendingSeconds }
        return out.filter { $0 > now }
    }
}
