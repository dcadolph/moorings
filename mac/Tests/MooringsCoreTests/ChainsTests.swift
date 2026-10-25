import Foundation
import Testing

@testable import MooringsCore

// Swift only: a non-looping chain stops on its last step.
@Test func testChainStepStops() {
    let chain = Chain(name: "A", steps: ["left-half", "maximize"])
    #expect(chain.step(press: 0) == "left-half")
    #expect(chain.step(press: 1) == "maximize")
    #expect(chain.step(press: 5) == "maximize")
    #expect(Chain(name: "E").step(press: 0) == nil)
}

// Swift only: a looping chain wraps to the first step.
@Test func testChainStepLoops() {
    let chain = Chain(name: "A", steps: ["left-half", "maximize"], loops: true)
    #expect(chain.step(press: 2) == "left-half")
    #expect(chain.step(press: 3) == "maximize")
}

// Swift only: a chain gets its action name from the prefix.
@Test func testChainActionName() {
    #expect(Chain(name: "Focus").actionName == "chain:Focus")
}

// Swift only: a valid chain has no problems, and extra names count as runnable.
@Test func testChainValid() {
    #expect(Chain(name: "A", steps: ["left-half", "size:Reading"]).validate(extra: ["size:Reading"]).isEmpty)
}

// Swift only: an unknown step name fails validation.
@Test func testChainUnknownStep() {
    #expect(!Chain(name: "A", steps: ["left-half", "no-such-action"]).validate().isEmpty)
}

// Swift only: a chain may not collide with an action, name itself, or name another chain.
@Test func testChainCollisionAndRecursion() {
    #expect(!Chain(name: "maximize", steps: ["left-half"]).validate().isEmpty)
    #expect(!Chain(name: "A", steps: ["chain:A"]).validate().isEmpty)
    #expect(!Chain(name: "A", steps: ["chain:B"]).validate().isEmpty)
    #expect(!Chain(name: "", steps: ["left-half"]).validate().isEmpty)
    #expect(!Chain(name: "A").validate().isEmpty)
}

// Swift only: a chain with missing keys decodes at the defaults.
@Test func testChainLenientDecode() throws {
    let chain = try JSONDecoder().decode(Chain.self, from: Data(#"{"name":"A"}"#.utf8))
    #expect(chain == Chain(name: "A"))
}

// Swift only: hidden names drop out of the menu and the rest keep their order.
@Test func testMenuVisible() {
    var menu = MenuChoices()
    menu.hidden = ["maximize", "center"]
    #expect(menu.visible(["left-half", "maximize", "right-half", "center"]) == ["left-half", "right-half"])
    #expect(MenuChoices().visible(["left-half"]) == ["left-half"])
}

// Swift only: pinned names keep their order, appear once, and drop names that no longer run.
@Test func testMenuPinned() {
    var menu = MenuChoices()
    menu.order = ["maximize", "chain:Gone", "left-half", "maximize", "no-such-action"]
    #expect(menu.pinned { Keymaps.known($0) && $0 != "chain:Gone" } == ["maximize", "left-half"])
    #expect(MenuChoices().pinned(Keymaps.known).isEmpty)
}
