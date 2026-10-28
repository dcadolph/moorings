import MooringsEngine

// FakeNotifier is a Notifier that records every message.
public final class FakeNotifier: Notifier {
    // Note is one message.
    public struct Note: Equatable, Sendable {
        // title is the message's title.
        public var title: String
        // body is the message's body.
        public var body: String
    }

    // notes records every message in order.
    public private(set) var notes: [Note] = []

    // init builds a notifier with no messages.
    public init() {}

    // notify records the message.
    public func notify(_ title: String, _ body: String) {
        notes.append(Note(title: title, body: body))
    }
}
