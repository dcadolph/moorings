import AppIntents
import AppKit

import MooringsCore
import MooringsEngine

// RunAction is the Shortcuts action that runs one moorings action by name, as a
// moorings://action?name= link does.
struct RunAction: AppIntent {
    static let title: LocalizedStringResource = "Run Moorings Action"
    static let description = IntentDescription("Run a moorings action, such as left-half, on the front window.")
    static let openAppWhenRun = false

    // name is the action to run, such as left-half, chain:<name> or workspace:<name>.
    @Parameter(title: "Action", optionsProvider: ActionOptions())
    var name: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$name)")
    }

    // perform runs the action and fails when moorings does not know it.
    @MainActor
    func perform() async throws -> some IntentResult {
        guard delegate.actions.runnable(name) else {
            throw RunActionError.unknown(name)
        }
        delegate.actions.run(name)
        return .result()
    }
}

// RunActionError is why a Shortcuts run of a moorings action failed.
enum RunActionError: Error, CustomLocalizedStringResourceConvertible {
    // unknown is an action name moorings does not know.
    case unknown(String)

    // localizedStringResource is the message Shortcuts shows.
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unknown(name):
            "Moorings has no action named \(name)."
        }
    }
}

// ActionOptions lists the action names Shortcuts offers for RunAction: every window action, then the
// saved chains, workspaces and profiles.
struct ActionOptions: DynamicOptionsProvider {
    // results returns the action names in menu order.
    @MainActor
    func results() async throws -> [String] {
        let fixed = ActionRunner.families.flatMap { $0.names + $0.groups.flatMap(\.names) }
            + Keymaps.windowNames + Keymaps.organizeNames + Keymaps.stashNames
        let choices = delegate.anchors.choices
        let saved = choices.chains.map(\.actionName) + choices.workspaces.keys.sorted().map { Keymaps.workspacePrefix + $0 }
            + choices.profiles.map { Profile.prefix + $0.name }
        var seen = Set<String>()
        return (fixed + saved).filter { seen.insert($0).inserted }
    }
}

// MooringsShortcuts offers RunAction in Shortcuts and Spotlight with no setup.
struct MooringsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunAction(), phrases: ["Run an action in \(.applicationName)"],
                    shortTitle: "Run Action", systemImageName: "macwindow")
    }
}
