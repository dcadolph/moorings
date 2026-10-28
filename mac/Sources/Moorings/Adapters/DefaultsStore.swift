import Foundation

import MooringsCore
import MooringsEngine

// DefaultsStore is the Mac ChoicesStore: the encoded choices under one user defaults key.
final class DefaultsStore: ChoicesStore {
    // key is the defaults key the choices live under.
    let key: String
    // asideKey is where load moves saved choices it cannot read: the key with .bad after it.
    var asideKey: String { key + ".bad" }
    // saved runs after each save with the choices saved, for the parts of the app a choice shows:
    // the menu bar icon and the ignore-list switch.
    let saved: (Choices) -> Void

    // init keeps the choices under key and tells saved after each save.
    init(key: String, saved: @escaping (Choices) -> Void) {
        self.key = key
        self.saved = saved
    }

    // load decodes the saved choices, or the defaults when none are saved. Saved choices it cannot
    // read move to asideKey, replacing older ones there, and load as the defaults with the reason.
    func load() -> Loaded {
        let defaults = UserDefaults.standard
        guard let saved = defaults.object(forKey: key) else { return Loaded(choices: Choices()) }
        let loaded =
            (saved as? Data).map { Choices.decode($0) }
            ?? Loaded(choices: Choices(), fallback: "the saved choices are not data")
        if loaded.fallback != nil {
            defaults.set(saved, forKey: asideKey)
            defaults.removeObject(forKey: key)
        }
        return loaded
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
