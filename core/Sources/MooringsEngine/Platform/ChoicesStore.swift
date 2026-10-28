import MooringsCore

// ChoicesStore loads and saves the user's choices.
public protocol ChoicesStore: AnyObject {
    // load returns the saved choices, or the defaults when none are saved.
    func load() -> Choices
    // save writes choices.
    func save(_ choices: Choices) throws
}
