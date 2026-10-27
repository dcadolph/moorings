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

    // plan returns .full when forced, when a full pass is overdue, or when no app was named by a
    // recent wake, and otherwise the apps that woke recently plus the apps whose listed windows
    // differ from the previous pass. A slow app is read only when it woke recently.
    public static func plan(
        now: Double, forced: Bool, lastFull: Double, fullWoke: Double, woke: [Int32: Double],
        listed: [Int32: [WindowID: Frame]], previous: [Int32: [WindowID: Frame]], slow: Set<Int32>
    ) -> PassPlan {
        if forced || now - lastFull >= fullSeconds || now - fullWoke < Pace.settleSeconds {
            return .full
        }
        let recent = Set(woke.filter { now - $0.value < Pace.settleSeconds }.keys)
        if recent.isEmpty {
            return .full
        }
        return .apps(recent.union(changed(listed: listed, previous: previous, slow: slow)))
    }

    // changed returns the apps not in slow whose listed windows differ from the previous ones.
    public static func changed(
        listed: [Int32: [WindowID: Frame]], previous: [Int32: [WindowID: Frame]], slow: Set<Int32>
    ) -> Set<Int32> {
        Set(listed.filter { !slow.contains($0.key) && differs($0.value, previous[$0.key]) }.keys)
    }

    // differs reports whether the listed windows have other ids than the previous ones or any frame
    // drifted by more than tolerance.
    static func differs(_ listed: [WindowID: Frame], _ previous: [WindowID: Frame]?) -> Bool {
        guard let previous, Set(listed.keys) == Set(previous.keys) else { return true }
        for (id, now) in listed {
            guard let was = previous[id] else { return true }
            if abs(now.x - was.x) > tolerance || abs(now.y - was.y) > tolerance
                || abs(now.w - was.w) > tolerance || abs(now.h - was.h) > tolerance
            {
                return true
            }
        }
        return false
    }
}
