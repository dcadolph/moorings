// Rows guards the writes a Settings row makes by the index it was drawn at, so a row drawn before
// its list changed never writes to another row or past the end.
extension Array {
    // still reports whether index i names the same row a view drew when the array had count rows.
    public func still(_ i: Int, of count: Int) -> Bool {
        self.count == count && indices.contains(i)
    }
}

extension Array where Element: Equatable {
    // still reports whether index i still holds element, as when the row was drawn.
    public func still(_ i: Int, holding element: Element) -> Bool {
        indices.contains(i) && self[i] == element
    }

    // move swaps the row at i, which must still hold element, with the row at j, and reports whether
    // it did.
    @discardableResult
    public mutating func move(_ i: Int, holding element: Element, to j: Int) -> Bool {
        guard still(i, holding: element), indices.contains(j) else { return false }
        swapAt(i, j)
        return true
    }

    // remove removes the row at i when it still holds element, and reports whether it did.
    @discardableResult
    public mutating func remove(_ i: Int, holding element: Element) -> Bool {
        guard still(i, holding: element) else { return false }
        remove(at: i)
        return true
    }
}
