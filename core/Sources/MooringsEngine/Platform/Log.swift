// Log records the engine's lines, each under a category.
public protocol Log: AnyObject {
    // note records one line under a category.
    func note(_ category: LogCategory, _ line: String)
}
