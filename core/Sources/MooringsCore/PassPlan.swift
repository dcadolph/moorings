// PassPlan is which apps one pass reads through Accessibility: every app, or only the apps by
// process id whose windows may have changed. Every other app is carried from the last pass with
// its frames from the window server list.
public enum PassPlan: Equatable, Sendable {
    case full
    case apps(Set<Int32>)

    // fullSeconds is the longest a run of passes goes without a full one.
    public static let fullSeconds = 10.0
    // tolerance is how far in points a listed frame may drift before its app is read again.
    public static let tolerance = 1.0
    // appsSeconds is the longest a full pass goes without asking every running app whether it shows
    // windows, so an app that turns regular after launch is watched.
    public static let appsSeconds = 60.0

    // refreshesApps reports whether a full pass asks every running app for its kind: when an app has
    // not yet taken its observer, or appsSeconds passed since the last time. last is nil before the
    // first time.
    public static func refreshesApps(now: Double, last: Double?, waiting: Bool) -> Bool {
        guard let last else { return true }
        return waiting || now - last >= appsSeconds
    }

    // plan returns .full when forced, which a recent wake that named no app is, when a full pass is
    // overdue, or when no app was named by a recent wake and no action's move is still echoing, and otherwise the apps that woke recently,
    // the apps whose listed windows differ from the previous pass, and the front app. A slow app is
    // read only when it woke recently. echoes holds the frames recent actions read back after moving
    // a window. The front app is left out when a listed window of it has an echo and it neither woke
    // nor changed, so the pass after an action reads nothing the action already read.
    public static func plan(
        now: Double, forced: Bool, lastFull: Double, woke: [Int32: Double],
        listed: [Int32: [WindowID: Frame]], previous: [Int32: [WindowID: Frame]], slow: Set<Int32>,
        front: Int32? = nil, echoes: [WindowID: Frame] = [:]
    ) -> PassPlan {
        if forced || now - lastFull >= fullSeconds {
            return .full
        }
        let recent = Set(woke.filter { now - $0.value < Pace.settleSeconds }.keys)
        if recent.isEmpty && echoes.isEmpty {
            return .full
        }
        var reads = recent.union(changed(listed: listed, previous: previous, slow: slow, echoes: echoes))
        if let front, !(listed[front] ?? [:]).keys.contains(where: { echoes[$0] != nil }) {
            reads.insert(front)
        }
        return .apps(reads)
    }

    // changed returns the apps not in slow whose listed windows differ from the previous ones. A
    // window listed within tolerance of its echo counts as unchanged.
    public static func changed(
        listed: [Int32: [WindowID: Frame]], previous: [Int32: [WindowID: Frame]], slow: Set<Int32>,
        echoes: [WindowID: Frame] = [:]
    ) -> Set<Int32> {
        Set(listed.filter { !slow.contains($0.key) && differs($0.value, previous[$0.key], echoes: echoes) }.keys)
    }

    // differs reports whether the listed windows have other ids than the previous ones or any frame
    // drifted by more than tolerance from both its previous frame and its echo.
    static func differs(_ listed: [WindowID: Frame], _ previous: [WindowID: Frame]?, echoes: [WindowID: Frame] = [:])
        -> Bool
    {
        guard let previous, Set(listed.keys) == Set(previous.keys) else { return true }
        for (id, now) in listed {
            guard let was = previous[id] else { return true }
            if !near(now, was) && !(echoes[id].map { near(now, $0) } ?? false) {
                return true
            }
        }
        return false
    }

    // near reports whether a and b differ by at most tolerance on every edge.
    static func near(_ a: Frame, _ b: Frame) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance
    }
}
