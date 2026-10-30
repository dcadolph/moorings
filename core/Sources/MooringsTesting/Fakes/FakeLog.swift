import MooringsEngine

// FakeLog is a Log that keeps every line, so engine tests assert on what was noted.
public final class FakeLog: Log {
    // Line is one noted line.
    public struct Line: Equatable, Sendable {
        // category is the part of the engine that noted it.
        public var category: LogCategory
        // text is the line.
        public var text: String

        // init builds a line.
        public init(_ category: LogCategory, _ text: String) {
            self.category = category
            self.text = text
        }
    }

    // lines lists every noted line in order.
    public private(set) var lines: [Line] = []
    // traces lists every traced line in order, apart from the noted ones.
    public private(set) var traces: [Line] = []

    // init builds an empty log.
    public init() {}

    // note keeps the line.
    public func note(_ category: LogCategory, _ line: String) {
        lines.append(Line(category, line))
    }

    // trace keeps the line apart from the noted ones.
    public func trace(_ category: LogCategory, _ line: String) {
        traces.append(Line(category, line))
    }
}
