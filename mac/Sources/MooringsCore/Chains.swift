import Foundation

// Chain is a named, ordered list of action names that runs one step per press, optionally looping.
public struct Chain: Equatable, Sendable, Codable {
    // prefix starts the action name of every chain.
    public static let prefix = "chain:"

    // name is the chain's title, without the prefix.
    public var name: String
    // steps are the action names in the order presses run them.
    public var steps: [String]
    // loops reports whether presses wrap to the first step after the last.
    public var loops: Bool

    // init builds a chain.
    public init(name: String, steps: [String] = [], loops: Bool = false) {
        self.name = name
        self.steps = steps
        self.loops = loops
    }

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case name, steps, loops
    }

    // init decodes a chain, keeping the default for any field missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        steps = (try? c.decodeIfPresent([String].self, forKey: .steps)) ?? []
        loops = (try? c.decodeIfPresent(Bool.self, forKey: .loops)) ?? false
    }

    // actionName is the name the chain runs under, chain: followed by its title.
    public var actionName: String { Chain.prefix + name }

    // step returns the action name the press with the given zero-based count runs, wrapping when the
    // chain loops and staying on the last step when it does not. It returns nil for an empty chain.
    public func step(press: Int) -> String? {
        guard !steps.isEmpty else { return nil }
        let index = max(press, 0)
        return loops ? steps[index % steps.count] : steps[min(index, steps.count - 1)]
    }

    // validate returns the problems with the chain: an empty or colliding name, no steps, and steps
    // that name an unknown action, the chain itself or another chain. The extra names are runnable
    // actions beyond the built-in ones, such as custom sizes.
    public func validate(extra: Set<String> = []) -> [String] {
        var problems: [String] = []
        if name.isEmpty {
            problems.append("chain has no name")
        } else if Keymaps.known(name) || Keymaps.known(actionName) || extra.contains(name) {
            problems.append("chain \(name) collides with an action name")
        }
        if steps.isEmpty {
            problems.append("chain \(name) has no steps")
        }
        for step in steps {
            if step.hasPrefix(Chain.prefix) {
                problems.append("chain \(name) names chain \(step): chains do not nest")
            } else if !(Keymaps.known(step) || extra.contains(step)) {
                problems.append("chain \(name) names unknown action \(step)")
            }
        }
        return problems
    }
}

// MenuChoices is the menu customization: the shown action names in order and the hidden ones.
public struct MenuChoices: Equatable, Sendable, Codable {
    // order lists the action names to show, in menu order.
    public var order: [String] = []
    // hidden lists the action names to leave out of the menu.
    public var hidden: [String] = []

    // init builds menu choices at the defaults.
    public init() {}

    // CodingKeys names the saved fields.
    private enum CodingKeys: String, CodingKey {
        case order, hidden
    }

    // init decodes menu choices, keeping the default for any field missing or unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = (try? c.decodeIfPresent([String].self, forKey: .order)) ?? []
        hidden = (try? c.decodeIfPresent([String].self, forKey: .hidden)) ?? []
    }
}
