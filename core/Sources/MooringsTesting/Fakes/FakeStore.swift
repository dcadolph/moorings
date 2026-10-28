import Foundation

import MooringsCore
import MooringsEngine

// FakeStore is a ChoicesStore that keeps the last saved choices in memory.
public final class FakeStore: ChoicesStore {
    // FakeError is the error save throws when failing is set.
    public struct FakeError: Error, Equatable {}

    // saved is the last saved choices, nil before the first save.
    public private(set) var saved: Choices?
    // saves counts the saves that succeeded.
    public private(set) var saves = 0
    // failing makes save throw.
    public var failing = false
    // initial is what load returns before the first save.
    private let initial: Choices
    // moved reports whether the choices were rewritten from outside since the last load or save.
    private var moved = false
    // spoiled is a payload put in the store from outside, read at the next load.
    private var spoiled: Data?
    // aside is the payload a load moved aside because it could not be read, nil when none was.
    public private(set) var aside: Data?

    // init builds a store that loads initial until something is saved.
    public init(_ initial: Choices = Choices()) {
        self.initial = initial
    }

    // load returns the last saved choices, or the initial ones. A spoiled payload that decodes
    // becomes the saved choices; one that does not moves aside and loads the defaults.
    public func load() -> Loaded {
        moved = false
        if let raw = spoiled {
            spoiled = nil
            let loaded = Choices.decode(raw)
            if loaded.fallback == nil {
                saved = loaded.choices
            } else {
                aside = raw
            }
            return loaded
        }
        return Loaded(choices: saved ?? initial)
    }

    // save keeps choices, or throws when failing is set.
    public func save(_ choices: Choices) throws {
        if failing {
            throw FakeError()
        }
        saved = choices
        saves += 1
        moved = false
        spoiled = nil
    }

    // changed reports whether rewrite ran since the last load or save.
    public func changed() -> Bool {
        moved
    }

    // rewrite puts choices in the store as another program writing the file would.
    public func rewrite(_ choices: Choices) {
        saved = choices
        spoiled = nil
        moved = true
    }

    // spoil puts payload in the store as the saved choices, as a damaged disk or a hand edit would.
    public func spoil(_ payload: Data) {
        saved = nil
        spoiled = payload
        moved = true
    }
}
