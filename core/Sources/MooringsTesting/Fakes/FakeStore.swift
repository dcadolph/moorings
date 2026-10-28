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

    // init builds a store that loads initial until something is saved.
    public init(_ initial: Choices = Choices()) {
        self.initial = initial
    }

    // load returns the last saved choices, or the initial ones.
    public func load() -> Choices {
        moved = false
        return saved ?? initial
    }

    // save keeps choices, or throws when failing is set.
    public func save(_ choices: Choices) throws {
        if failing {
            throw FakeError()
        }
        saved = choices
        saves += 1
        moved = false
    }

    // changed reports whether rewrite ran since the last load or save.
    public func changed() -> Bool {
        moved
    }

    // rewrite puts choices in the store as another program writing the file would.
    public func rewrite(_ choices: Choices) {
        saved = choices
        moved = true
    }
}
