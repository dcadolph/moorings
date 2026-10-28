import Testing

@testable import MooringsCore

// WindowTraitsCase is one window's traits and the decisions they must give.
struct WindowTraitsCase: Sendable {
    // Traits is what the read returned.
    var Traits: WindowTraits
    // WantDocument is whether the window is a document window.
    var WantDocument: Bool
    // WantFilePanel is whether the window is an open or save panel.
    var WantFilePanel: Bool
    // WantMovable is whether moorings may move the window.
    var WantMovable: Bool
}

// traitsFrame is a frame any window could have.
let traitsFrame = Frame(x: 0, y: 25, w: 800, h: 600)

// windowTraitsCases covers each rule of WindowTraits.
let windowTraitsCases: [WindowTraitsCase] = [
    // Test 0: A standard window with a frame is a movable document.
    WindowTraitsCase(
        Traits: WindowTraits(role: "AXWindow", subrole: "AXStandardWindow", frame: traitsFrame),
        WantDocument: true, WantFilePanel: false, WantMovable: true),
    // Test 1: A dialog with a zoom button is a document, as TextEdit reports its documents.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXDialog", hasZoomButton: true,
            frame: traitsFrame),
        WantDocument: true, WantFilePanel: false, WantMovable: true),
    // Test 2: A dialog without a zoom button is not a document.
    WindowTraitsCase(
        Traits: WindowTraits(role: "AXWindow", subrole: "AXDialog", frame: traitsFrame),
        WantDocument: false, WantFilePanel: false, WantMovable: false),
    // Test 3: A floating window is not a document even with a zoom button.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXFloatingWindow", hasZoomButton: true,
            frame: traitsFrame),
        WantDocument: false, WantFilePanel: false, WantMovable: false),
    // Test 4: A minimized document is not movable.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXStandardWindow", minimized: true,
            frame: traitsFrame),
        WantDocument: true, WantFilePanel: false, WantMovable: false),
    // Test 5: A document whose frame cannot be read is not movable.
    WindowTraitsCase(
        Traits: WindowTraits(role: "AXWindow", subrole: "AXStandardWindow"),
        WantDocument: true, WantFilePanel: false, WantMovable: false),
    // Test 6: A standard subrole on an element that is not a window is not movable.
    WindowTraitsCase(
        Traits: WindowTraits(role: "AXSheet", subrole: "AXStandardWindow", frame: traitsFrame),
        WantDocument: true, WantFilePanel: false, WantMovable: false),
    // Test 7: An open panel is a file panel.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXDialog", identifier: "open-panel",
            frame: traitsFrame),
        WantDocument: false, WantFilePanel: true, WantMovable: false),
    // Test 8: A save panel is a file panel.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXStandardWindow",
            identifier: "save-panel", frame: traitsFrame),
        WantDocument: true, WantFilePanel: true, WantMovable: true),
    // Test 9: Any other identifier is not a file panel.
    WindowTraitsCase(
        Traits: WindowTraits(
            role: "AXWindow", subrole: "AXDialog", identifier: "print-panel",
            frame: traitsFrame),
        WantDocument: false, WantFilePanel: false, WantMovable: false),
    // Test 10: Nothing read decides nothing in the window's favor.
    WindowTraitsCase(Traits: WindowTraits(), WantDocument: false, WantFilePanel: false, WantMovable: false),
]

@Test(arguments: windowTraitsCases)
func testWindowTraits(test: WindowTraitsCase) {
    #expect(test.Traits.document == test.WantDocument)
    #expect(test.Traits.filePanel == test.WantFilePanel)
    #expect(test.Traits.eligible == (test.WantDocument || test.WantFilePanel))
    #expect(test.Traits.movable == test.WantMovable)
}
