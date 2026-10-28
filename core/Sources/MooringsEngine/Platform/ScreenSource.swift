import MooringsCore

// ScreenSource reads the attached displays.
public protocol ScreenSource: AnyObject {
    // current returns the attached displays.
    func current() -> Screens
    // quirks is what ActionTarget needs beyond frames: notched screens, Stage Manager strips.
    // Windows returns .none.
    func quirks(_ screens: Screens) -> ScreenQuirks
    // displaySetKey names the set of displays in screens, the same whatever order they come in, so a
    // workspace can be tied to it.
    func displaySetKey(_ screens: Screens) -> String
}

extension ScreenSource {
    // displaySetKey keys the displays by their full frames, which is what the Mac uses.
    public func displaySetKey(_ screens: Screens) -> String {
        Workspaces.signature(screens.full)
    }
}
