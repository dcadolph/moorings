import Testing

@testable import MooringsCore

// Test 0: A row drawn before its list changed size is refused, and one drawn at the current size
// is allowed only inside the list.
@Test(arguments: [
    (rows: ["a", "b", "c"], i: 1, count: 3, want: true),
    (rows: ["a", "b"], i: 1, count: 3, want: false),
    (rows: ["a", "b", "c", "d"], i: 1, count: 3, want: false),
    (rows: ["a", "b", "c"], i: 3, count: 3, want: false),
    (rows: [], i: 0, count: 0, want: false),
])
func testStillByCount(test: (rows: [String], i: Int, count: Int, want: Bool)) {
    #expect(test.rows.still(test.i, of: test.count) == test.want)
}

// Test 1: A row is still its own only while its index holds the element it was drawn with.
@Test(arguments: [
    (rows: ["a", "b", "c"], i: 1, element: "b", want: true),
    (rows: ["a", "c"], i: 1, element: "b", want: false),
    (rows: ["a"], i: 1, element: "b", want: false),
    (rows: ["a", "b"], i: -1, element: "b", want: false),
])
func testStillHolding(test: (rows: [String], i: Int, element: String, want: Bool)) {
    #expect(test.rows.still(test.i, holding: test.element) == test.want)
}

// Test 2: A stale remove after an earlier row was removed leaves the list alone instead of removing
// the row that slid into its place or trapping past the end.
@Test func testRemoveStale() {
    var rows = ["a", "b", "c"]
    let first = rows.remove(0, holding: "a")
    let second = rows.remove(1, holding: "b")
    let third = rows.remove(2, holding: "c")
    #expect(first)
    #expect(!second)
    #expect(!third)
    #expect(rows == ["b", "c"])
}

// Test 3: A move swaps only a row still in place with a neighbor inside the list.
@Test(arguments: [
    (i: 1, element: "b", j: 0, wantMoved: true, wantRows: ["b", "a", "c"]),
    (i: 1, element: "c", j: 0, wantMoved: false, wantRows: ["a", "b", "c"]),
    (i: 2, element: "c", j: 3, wantMoved: false, wantRows: ["a", "b", "c"]),
    (i: 0, element: "a", j: -1, wantMoved: false, wantRows: ["a", "b", "c"]),
])
func testMove(test: (i: Int, element: String, j: Int, wantMoved: Bool, wantRows: [String])) {
    var rows = ["a", "b", "c"]
    let moved = rows.move(test.i, holding: test.element, to: test.j)
    #expect(moved == test.wantMoved)
    #expect(rows == test.wantRows)
}
