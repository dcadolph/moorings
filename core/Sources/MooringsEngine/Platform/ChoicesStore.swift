import MooringsCore

// ChoicesStore loads and saves the user's choices.
public protocol ChoicesStore: AnyObject {
    // load returns the saved choices, or the defaults when none are saved. Saved choices it cannot
    // read load as the defaults with the reason, and the store moves them aside so they are not lost.
    func load() -> Loaded
    // save writes choices.
    func save(_ choices: Choices) throws
    // changed reports whether the saved choices moved under the store since load or save last read
    // them; a store nothing else writes reports false.
    func changed() -> Bool
}
