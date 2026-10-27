import Testing

@testable import MooringsCore

// PassPlanCase is one call to PassPlan.plan and the plan it must return.
struct PassPlanCase: Sendable {
    // Now is when the pass runs.
    var Now = 100.0
    // Forced reports whether the pass must read every app.
    var Forced = false
    // LastFull is when the last full pass ran.
    var LastFull = 95.0
    // FullWoke is when the last wake that named no app came.
    var FullWoke = 0.0
    // Woke maps a process id to when its last event came.
    var Woke: [Int32: Double] = [:]
    // Listed holds the frames from the window server list now.
    var Listed: [Int32: [WindowID: Frame]] = [:]
    // Previous holds the frames the last pass saw.
    var Previous: [Int32: [WindowID: Frame]] = [:]
    // Slow holds the apps whose reads cost too much to repeat without a wake.
    var Slow: Set<Int32> = []
    // WantPlan is the plan the pass follows.
    var WantPlan: PassPlan
}

let planA: [WindowID: Frame] = [1: Frame(x: 0, y: 0, w: 100, h: 100)]

// passPlanCases covers each rule of the plan in order.
let passPlanCases: [PassPlanCase] = [
    // Test 0: A forced pass reads every app.
    PassPlanCase(Forced: true, Woke: [10: 99], WantPlan: .full),
    // Test 1: A full pass overdue by fullSeconds wins over a recent app wake.
    PassPlanCase(LastFull: 90, Woke: [10: 99], WantPlan: .full),
    // Test 2: A wake that named no app is still settling.
    PassPlanCase(FullWoke: 99, Woke: [10: 99], WantPlan: .full),
    // Test 3: Wakes older than settleSeconds name nothing.
    PassPlanCase(Woke: [10: 97], WantPlan: .full),
    // Test 4: One recent app with an unchanged list is the only one read.
    PassPlanCase(
        Woke: [10: 99, 11: 90], Listed: [10: planA, 11: planA], Previous: [10: planA, 11: planA],
        WantPlan: .apps([10])),
    // Test 5: A clean app whose frame moved by more than tolerance is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 2.5, y: 0, w: 100, h: 100)]],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10, 11])),
    // Test 6: A clean app whose frame moved by exactly tolerance is not added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 1, y: -1, w: 101, h: 99)]],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10])),
    // Test 7: A clean app with a new window id is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA.merging([2: planA[1]!]) { a, _ in a }],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10, 11])),
    // Test 8: A clean app that lost a window id is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA],
        Previous: [10: planA, 11: planA.merging([2: planA[1]!]) { a, _ in a }],
        WantPlan: .apps([10, 11])),
    // Test 9: An app listed now and missing from previous is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA], Previous: [10: planA],
        WantPlan: .apps([10, 11])),
    // Test 10: A slow app whose list changed is not added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 50, y: 0, w: 100, h: 100)]],
        Previous: [10: planA, 11: planA], Slow: [11], WantPlan: .apps([10])),
    // Test 11: A slow app that woke recently is included.
    PassPlanCase(
        Woke: [10: 99, 11: 99], Listed: [10: planA, 11: planA], Previous: [10: planA, 11: planA],
        Slow: [11], WantPlan: .apps([10, 11])),
]

@Test(arguments: passPlanCases)
func testPassPlan(test: PassPlanCase) {
    let got = PassPlan.plan(
        now: test.Now, forced: test.Forced, lastFull: test.LastFull, fullWoke: test.FullWoke,
        woke: test.Woke, listed: test.Listed, previous: test.Previous, slow: test.Slow)
    #expect(got == test.WantPlan)
}

// Test 12: changed names the apps whose list moved, leaving unchanged and slow apps out.
@Test func testPassPlanChanged() {
    let moved: [WindowID: Frame] = [1: Frame(x: 50, y: 0, w: 100, h: 100)]
    let got = PassPlan.changed(listed: [10: planA, 11: moved, 12: moved], previous: [10: planA, 11: planA, 12: planA],
                               slow: [12])
    #expect(got == [11])
}
