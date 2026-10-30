import MooringsCore

// Keys reads whether the user's shortcuts are on, binds them, takes keys for the length of a hold,
// and spells shortcuts the platform's way.
public protocol Keys: AnyObject {
    // shortcutsOn reports whether the user's shortcuts are enabled, since a hold is one.
    var shortcutsOn: Bool { get }
    // bind registers the shortcuts in map, replacing those bound before, and delivers each press to
    // the engine's action by name.
    func bind(_ map: [String: Shortcut])
    // grab takes keys for the length of a hold and delivers each press to handler by tag. It returns
    // how many were taken. A second grab replaces the first.
    func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int
    // ungrab lets the grabbed keys go.
    func ungrab()
    // claim takes keys for as long as a state lasts and delivers each press to handler by tag. It
    // returns how many were taken. A claim is independent of a grab: a grab, an ungrab or a bind in
    // between leaves it delivering. A second claim replaces the first.
    func claim(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int
    // unclaim lets the claimed keys go.
    func unclaim()
    // spell writes a shortcut the way the platform's keyboard does.
    func spell(_ s: Shortcut) -> String
}
