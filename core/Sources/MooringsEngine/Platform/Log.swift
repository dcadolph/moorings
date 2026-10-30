// Log records the engine's lines, each under a category.
public protocol Log: AnyObject {
    // note records one line under a category.
    func note(_ category: LogCategory, _ line: String)
    // trace records one line under a category at a level kept only while someone streams it, for
    // lines too frequent to note, such as one per pass.
    func trace(_ category: LogCategory, _ line: String)
}

extension Log {
    // trace drops the line on a platform that keeps no streamed level.
    public func trace(_ category: LogCategory, _ line: String) {}
}
