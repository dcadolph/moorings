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
    // spell writes a shortcut the way the platform's keyboard does.
    func spell(_ s: Shortcut) -> String
}
