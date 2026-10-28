import Foundation

import MooringsCore
import MooringsEngine

// DefaultsStore is the Mac ChoicesStore: the encoded choices under one user defaults key.
final class DefaultsStore: ChoicesStore {
    // key is the defaults key the choices live under.
    private let key: String
    // saved runs after each save with the choices saved, for the parts of the app a choice shows:
    // the menu bar icon and the ignore-list switch.
    let saved: (Choices) -> Void

    // init keeps the choices under key and tells saved after each save.
    init(key: String, saved: @escaping (Choices) -> Void) {
        self.key = key
        self.saved = saved
    }

    // load decodes the saved choices, or the defaults when none are saved.
    func load() -> Choices {
        Choices.decode(UserDefaults.standard.data(forKey: key) ?? Data())
    }

    // save encodes choices under the key.
    func save(_ choices: Choices) throws {
        UserDefaults.standard.set(try Choices.encode(choices), forKey: key)
        saved(choices)
    }

    // changed is false: Moorings is the only writer of its defaults, and a choice changed under it is
    // read at the next launch.
    func changed() -> Bool {
        false
    }
}
