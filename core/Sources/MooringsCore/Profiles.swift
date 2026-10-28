import Foundation

// ProfileSettings holds the choices a profile switches. It never holds anchors, workspaces or profiles.
public struct ProfileSettings: Equatable, Sendable, Codable {
    // keymap names the built-in shortcut set.
    public var keymap: String = Keymap.rectangle.rawValue
    // shortcuts maps an action to its shortcut, without the profile shortcuts.
    public var shortcuts: [String: StoredShortcut?] = [:]
    // sizes lists the custom sizes.
    public var sizes: [StoredSize] = []
    // gapPx is the gap in points window actions leave around a window.
    public var gapPx: Double = 0
    // snap reports whether dragging a window to an edge snaps it.
    public var snap: Bool = true
    // snapping holds the drag snap configuration and footprint style.
    public var snapping: SnapChoices = SnapChoices()
    // behavior holds the window action behavior choices.
    public var behavior: Behaviors = Behaviors()
    // stacking holds the cycling overlap offset and stack badge choices.
    public var stacking: StackChoices = StackChoices()
    // chains holds the saved action chains.
    public var chains: [Chain] = []
    // menu holds the menu order and the hidden actions.
    public var menu: MenuChoices = MenuChoices()
    // appRules holds the per-app rules.
    public var appRules: [AppRule] = []
    // mouseButtons maps an extra mouse button to the action it runs.
    public var mouseButtons: [String: String] = [:]
    // buttonClicks maps a title bar button and modifier to the action a click runs.
    public var buttonClicks: [String: String] = [:]

    // init builds settings at the defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case keymap, shortcuts, sizes, gapPx, snap, snapping, behavior, stacking, chains, menu, appRules
        case mouseButtons, buttonClicks
    }

    // init decodes saved settings, keeping what is readable and defaulting the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keymap = (try? c.decodeIfPresent(String.self, forKey: .keymap)) ?? Keymap.rectangle.rawValue
        shortcuts = (try? c.decodeIfPresent([String: StoredShortcut?].self, forKey: .shortcuts)) ?? [:]
        sizes = (try? c.decodeIfPresent([StoredSize].self, forKey: .sizes)) ?? []
        gapPx = (try? c.decodeIfPresent(Double.self, forKey: .gapPx)) ?? 0
        snap = (try? c.decodeIfPresent(Bool.self, forKey: .snap)) ?? true
        snapping = (try? c.decodeIfPresent(SnapChoices.self, forKey: .snapping)) ?? SnapChoices()
        behavior = (try? c.decodeIfPresent(Behaviors.self, forKey: .behavior)) ?? Behaviors()
        stacking = (try? c.decodeIfPresent(StackChoices.self, forKey: .stacking)) ?? StackChoices()
        chains = (try? c.decodeIfPresent([Chain].self, forKey: .chains)) ?? []
        menu = (try? c.decodeIfPresent(MenuChoices.self, forKey: .menu)) ?? MenuChoices()
        appRules = (try? c.decodeIfPresent([AppRule].self, forKey: .appRules)) ?? []
        mouseButtons = (try? c.decodeIfPresent([String: String].self, forKey: .mouseButtons)) ?? [:]
        buttonClicks = (try? c.decodeIfPresent([String: String].self, forKey: .buttonClicks)) ?? [:]
    }
}

// Profile is a named set of switchable settings and the workspaces recalled with it.
public struct Profile: Equatable, Sendable, Codable {
    // prefix starts the action name of every profile.
    public static let prefix = "profile:"

    // name is the profile's title, without the prefix.
    public var name: String
    // settings holds the switchable choices.
    public var settings: ProfileSettings
    // workspaces lists the workspace names recalled in order when the profile is applied.
    public var workspaces: [String]

    // init builds a profile.
    public init(name: String, settings: ProfileSettings = ProfileSettings(), workspaces: [String] = []) {
        self.name = name
        self.settings = settings
        self.workspaces = workspaces
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case name, settings, workspaces
    }

    // init decodes a saved profile, defaulting what is missing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        settings = (try? c.decodeIfPresent(ProfileSettings.self, forKey: .settings)) ?? ProfileSettings()
        workspaces = (try? c.decodeIfPresent([String].self, forKey: .workspaces)) ?? []
    }

    // actionName is the name the profile runs under, profile: followed by its title.
    public var actionName: String { Profile.prefix + name }
}

// Profiles checks saved profiles.
public enum Profiles {
    // validate returns the problems in profiles, given the names of the saved workspaces.
    public static func validate(_ profiles: [Profile], workspaces: Set<String>) -> [String] {
        var problems: [String] = []
        var seen: Set<String> = []
        for profile in profiles {
            if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("a profile has no name")
            } else if !seen.insert(profile.name).inserted {
                problems.append("duplicate profile name \(profile.name)")
            }
            for ws in profile.workspaces where !workspaces.contains(ws) {
                problems.append("profile \(profile.name) names unknown workspace \(ws)")
            }
        }
        return problems
    }

    // switchMessage words the one banner a profile switch shows: the workspaces recalled, the ones
    // that do not exist and the windows recall could not place. paused means a pause held back the
    // profile's workspaces.
    public static func switchMessage(recalled: [String], missing: [String], missed: Int, paused: Bool = false) -> String
    {
        if paused {
            return "Switched. Workspaces are not recalled while Moorings is paused."
        }
        var parts = [recalled.isEmpty ? "Switched." : "Switched and recalled \(recalled.joined(separator: ", "))."]
        if !missing.isEmpty {
            let names = missing.joined(separator: ", ")
            parts.append(missing.count == 1 ? "No workspace is named \(names)." : "No workspaces are named \(names).")
        }
        if missed > 0 {
            parts.append(
                missed == 1
                    ? "1 window had no running app or display."
                    : "\(missed) windows had no running app or display.")
        }
        return parts.joined(separator: " ")
    }
}

extension Choices {
    // profileSettings snapshots the switchable fields, leaving out the profile shortcuts.
    public func profileSettings() -> ProfileSettings {
        var s = ProfileSettings()
        s.keymap = keymap
        s.shortcuts = shortcuts.filter { !$0.key.hasPrefix(Profile.prefix) }
        s.sizes = sizes
        s.gapPx = gapPx
        s.snap = snap
        s.snapping = snapping
        s.behavior = behavior
        s.stacking = stacking
        s.chains = chains
        s.menu = menu
        s.appRules = appRules
        s.mouseButtons = mouseButtons
        s.buttonClicks = buttonClicks
        return s
    }

    // applying returns choices with the profile's settings in place and activeProfile set. The
    // profile shortcuts stay as they are, and nothing outside the settings changes.
    public func applying(_ profile: Profile) -> Choices {
        var c = self
        let s = profile.settings
        let kept = shortcuts.filter { $0.key.hasPrefix(Profile.prefix) }
        c.keymap = s.keymap
        c.shortcuts = kept.merging(s.shortcuts) { own, _ in own }
        c.sizes = s.sizes
        c.gapPx = s.gapPx
        c.snap = s.snap
        c.snapping = s.snapping
        c.behavior = s.behavior
        c.stacking = s.stacking
        c.chains = s.chains
        c.menu = s.menu
        c.appRules = s.appRules
        c.mouseButtons = s.mouseButtons
        c.buttonClicks = s.buttonClicks
        c.activeProfile = profile.name
        return c
    }

    // renameProfile renames the profile at index to name and moves its shortcut and menu entry to the
    // new action name. It does nothing when index is out of range or another profile has the name.
    public mutating func renameProfile(at index: Int, to name: String) {
        guard profiles.indices.contains(index), !profiles.contains(where: { $0.name == name }) else { return }
        let old = profiles[index].actionName
        let wasActive = activeProfile == profiles[index].name
        profiles[index].name = name
        let new = profiles[index].actionName
        if let sc = shortcuts.removeValue(forKey: old) {
            shortcuts[new] = sc
        }
        menu.order = menu.order.map { $0 == old ? new : $0 }
        if wasActive {
            activeProfile = name
        }
    }
}
