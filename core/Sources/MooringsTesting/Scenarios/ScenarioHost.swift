import MooringsCore
import MooringsEngine

// ScenarioHost is what a scenario needs from the platform beyond a ContractHost: putting a window
// where a person would from outside the store, and a picture of the screen for the report.
public protocol ScenarioHost: ContractHost {
    // place moves the window with id to frame from outside the store, the way a person or the app
    // itself would, and reports whether the host could.
    func place(_ id: WindowID, at frame: Frame) -> Bool
    // drag presses on the window with id at Scenarios.grab of its frame, moves the pointer by offset
    // with the keys in held down, and lets go, the way a person drags a window by its title bar, so
    // the engine's drag follower hears it the way the platform's pointer stream tells it. It reports
    // whether the host could.
    func drag(_ id: WindowID, by offset: Point, held: Modifiers) -> Bool
    // shot saves a picture of the screen under name and returns where it went, nil when the host
    // takes none.
    func shot(_ name: String) -> String?
}

extension ScenarioHost {
    // shot takes no picture.
    public func shot(_ name: String) -> String? {
        nil
    }
}
