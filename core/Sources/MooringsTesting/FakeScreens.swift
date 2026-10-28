import MooringsCore
import MooringsEngine

// FakeScreens is a ScreenSource that returns whatever displays a test sets.
public final class FakeScreens: ScreenSource {
    // screens is what current returns.
    public var screens: Screens
    // screenQuirks is what quirks returns.
    public var screenQuirks: ScreenQuirks

    // init builds the source from its displays and quirks.
    public init(_ screens: Screens, quirks: ScreenQuirks = .none) {
        self.screens = screens
        self.screenQuirks = quirks
    }

    // ultrawide builds a source with one 3440x1440 ultrawide, its usable frame below a 25 point bar.
    public static func ultrawide() -> FakeScreens {
        let full = Frame(x: 0, y: 0, w: 3440, h: 1440)
        let usable = Frame(x: 0, y: 25, w: 3440, h: 1415)
        return FakeScreens(Screens(full: [full], usable: [usable], ultrawide: 0))
    }

    // current returns the displays the test set.
    public func current() -> Screens {
        screens
    }

    // quirks returns the quirks the test set.
    public func quirks(_ screens: Screens) -> ScreenQuirks {
        screenQuirks
    }
}
