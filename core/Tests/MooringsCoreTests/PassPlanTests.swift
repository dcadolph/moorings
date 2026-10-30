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
    // Woke maps a process id to when its last event came.
    var Woke: [Int32: Double] = [:]
    // Listed holds the frames from the window server list now.
    var Listed: [Int32: [WindowID: Frame]] = [:]
    // Previous holds the frames the last pass saw.
    var Previous: [Int32: [WindowID: Frame]] = [:]
    // Slow holds the apps whose reads cost too much to repeat without a wake.
    var Slow: Set<Int32> = []
    // Front is the front app.
    var Front: Int32?
    // Echoes holds the frames recent actions read back after moving a window.
    var Echoes: [WindowID: Frame] = [:]
    // WantPlan is the plan the pass follows.
    var WantPlan: PassPlan
}

let planA: [WindowID: Frame] = [1: Frame(x: 0, y: 0, w: 100, h: 100)]
// planMoved is planA after an action moved its window.
let planMoved: [WindowID: Frame] = [1: Frame(x: 500, y: 0, w: 300, h: 100)]
// planOther is another app's window.
let planOther: [WindowID: Frame] = [3: Frame(x: 0, y: 0, w: 100, h: 100)]
// planTwo is two windows of one app before an action moved window 1.
let planTwo: [WindowID: Frame] = [1: Frame(x: 0, y: 0, w: 100, h: 100), 2: Frame(x: 0, y: 200, w: 100, h: 100)]

// passPlanCases covers each rule of the plan in order.
let passPlanCases: [PassPlanCase] = [
    // Test 0: A forced pass reads every app.
    PassPlanCase(Forced: true, Woke: [10: 99], WantPlan: .full),
    // Test 1: A full pass overdue by fullSeconds wins over a recent app wake.
    PassPlanCase(LastFull: 90, Woke: [10: 99], WantPlan: .full),
    // Test 2: Wakes older than settleSeconds name nothing.
    PassPlanCase(Woke: [10: 97], WantPlan: .full),
    // Test 3: One recent app with an unchanged list is the only one read.
    PassPlanCase(
        Woke: [10: 99, 11: 90], Listed: [10: planA, 11: planA], Previous: [10: planA, 11: planA],
        WantPlan: .apps([10])),
    // Test 4: A clean app whose frame moved by more than tolerance is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 2.5, y: 0, w: 100, h: 100)]],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10, 11])),
    // Test 5: A clean app whose frame moved by exactly tolerance is not added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 1, y: -1, w: 101, h: 99)]],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10])),
    // Test 6: A clean app with a new window id is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA.merging([2: planA[1]!]) { a, _ in a }],
        Previous: [10: planA, 11: planA], WantPlan: .apps([10, 11])),
    // Test 7: A clean app that lost a window id is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA],
        Previous: [10: planA, 11: planA.merging([2: planA[1]!]) { a, _ in a }],
        WantPlan: .apps([10, 11])),
    // Test 8: An app listed now and missing from previous is added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: planA], Previous: [10: planA],
        WantPlan: .apps([10, 11])),
    // Test 9: A slow app whose list changed is not added.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planA, 11: [1: Frame(x: 50, y: 0, w: 100, h: 100)]],
        Previous: [10: planA, 11: planA], Slow: [11], WantPlan: .apps([10])),
    // Test 10: A slow app that woke recently is included.
    PassPlanCase(
        Woke: [10: 99, 11: 99], Listed: [10: planA, 11: planA], Previous: [10: planA, 11: planA],
        Slow: [11], WantPlan: .apps([10, 11])),
    // Test 11: A window listed at its echo is not a change.
    PassPlanCase(
        Listed: [10: planMoved], Previous: [10: planA], Echoes: [1: planMoved[1]!], WantPlan: .apps([])),
    // Test 12: A window off both its echo and its previous frame is a change.
    PassPlanCase(
        Listed: [10: [1: Frame(x: 600, y: 0, w: 300, h: 100)]], Previous: [10: planA], Echoes: [1: planMoved[1]!],
        WantPlan: .apps([10])),
    // Test 13: A quiet front app with an echoed window is not read.
    PassPlanCase(
        Listed: [10: planMoved, 11: planOther], Previous: [10: planA, 11: planOther], Front: 10,
        Echoes: [1: planMoved[1]!], WantPlan: .apps([])),
    // Test 14: A front app with an echoed window that also woke is read.
    PassPlanCase(
        Woke: [10: 99], Listed: [10: planMoved], Previous: [10: planA], Front: 10, Echoes: [1: planMoved[1]!],
        WantPlan: .apps([10])),
    // Test 15: A front app with no echo is read.
    PassPlanCase(
        Woke: [11: 99], Listed: [10: planA, 11: planA], Previous: [10: planA, 11: planA], Front: 10,
        WantPlan: .apps([10, 11])),
    // Test 16: A front app with an echoed window whose other window moved is read.
    PassPlanCase(
        Listed: [10: [1: planMoved[1]!, 2: Frame(x: 0, y: 400, w: 100, h: 100)]], Previous: [10: planTwo],
        Front: 10, Echoes: [1: planMoved[1]!], WantPlan: .apps([10])),
    // Test 17: No recent wake and no echo plans a full pass.
    PassPlanCase(Listed: [10: planA], Previous: [10: planA], Front: 10, WantPlan: .full),
    // Test 18: No recent wake and a live echo plans an apps pass.
    PassPlanCase(
        Listed: [10: planMoved, 11: planOther], Previous: [10: planA, 11: planOther], Front: 11,
        Echoes: [1: planMoved[1]!], WantPlan: .apps([11])),
]

@Test(arguments: passPlanCases)
func testPassPlan(test: PassPlanCase) {
    let got = PassPlan.plan(
        now: test.Now, forced: test.Forced, lastFull: test.LastFull,
        woke: test.Woke, listed: test.Listed, previous: test.Previous, slow: test.Slow, front: test.Front,
        echoes: test.Echoes)
    #expect(got == test.WantPlan)
}

// Test 12: changed names the apps whose list moved, leaving unchanged and slow apps out.
@Test func testPassPlanChanged() {
    let moved: [WindowID: Frame] = [1: Frame(x: 50, y: 0, w: 100, h: 100)]
    let got = PassPlan.changed(
        listed: [10: planA, 11: moved, 12: moved], previous: [10: planA, 11: planA, 12: planA],
        slow: [12])
    #expect(got == [11])
}

// RefreshAppsCase is one call to PassPlan.refreshesApps and its answer.
struct RefreshAppsCase: Sendable {
    // Now is when the full pass runs.
    var Now = 100.0
    // Last is when the running apps were last asked, nil before the first time.
    var Last: Double?
    // Waiting reports whether an app has not yet taken its observer.
    var Waiting = false
    // WantRefresh is whether the pass asks every running app.
    var WantRefresh: Bool
}

// refreshAppsCases covers each rule of refreshesApps.
let refreshAppsCases: [RefreshAppsCase] = [
    // Test 13: The first full pass asks.
    RefreshAppsCase(Last: nil, WantRefresh: true),
    // Test 14: A pass soon after the last ask does not.
    RefreshAppsCase(Last: 95, WantRefresh: false),
    // Test 15: A pending observer asks on every full pass.
    RefreshAppsCase(Last: 95, Waiting: true, WantRefresh: true),
    // Test 16: appsSeconds after the last ask, the pass asks again.
    RefreshAppsCase(Now: 160, Last: 100, WantRefresh: true),
    // Test 17: Just under appsSeconds it does not.
    RefreshAppsCase(Now: 159.9, Last: 100, WantRefresh: false),
]

@Test(arguments: refreshAppsCases)
func testRefreshesApps(test: RefreshAppsCase) {
    #expect(PassPlan.refreshesApps(now: test.Now, last: test.Last, waiting: test.Waiting) == test.WantRefresh)
}

// CarriesCase is one call to PassPlan.carries and its answer.
struct CarriesCase: Sendable {
    // Now is when the pass runs.
    var Now = 100.0
    // Forced reports whether the pass must read every app.
    var Forced = false
    // LastFull is when the last full pass ran.
    var LastFull = 95.0
    // LastScan is when the last scan ran.
    var LastScan = 99.0
    // Woke maps a process id to when its last event came.
    var Woke: [Int32: Double] = [:]
    // Placed maps each window an action placed to when it did.
    var Placed: [WindowID: Double] = [1: 99.5]
    // Listed holds the windows on the last window server list.
    var Listed: Set<WindowID> = [1, 2]
    // WantCarry is whether the pass carries the last list.
    var WantCarry: Bool
}

// carriesCases covers each rule of carries.
let carriesCases: [CarriesCase] = [
    // Test 19: A pass after an action's move alone carries the list.
    CarriesCase(WantCarry: true),
    // Test 20: A forced pass lists.
    CarriesCase(Forced: true, WantCarry: false),
    // Test 21: A pass with a full one due lists.
    CarriesCase(LastFull: 90, WantCarry: false),
    // Test 22: An app's event since the last scan makes the pass list.
    CarriesCase(Woke: [10: 99.8], WantCarry: false),
    // Test 23: An event before the last scan does not.
    CarriesCase(Woke: [10: 98], WantCarry: true),
    // Test 24: A placement before the last scan does not count, so the pass lists.
    CarriesCase(Placed: [1: 98], WantCarry: false),
    // Test 25: No placement at all lists.
    CarriesCase(Placed: [:], WantCarry: false),
    // Test 26: A placed window missing from the last list makes the pass list.
    CarriesCase(Placed: [3: 99.5], WantCarry: false),
    // Test 27: Two placements since the last scan, both listed, carry.
    CarriesCase(Placed: [1: 99.5, 2: 99.6], WantCarry: true),
]

@Test(arguments: carriesCases)
func testCarries(test: CarriesCase) {
    let got = PassPlan.carries(
        now: test.Now, forced: test.Forced, lastFull: test.LastFull, lastScan: test.LastScan, woke: test.Woke,
        placed: test.Placed, listed: test.Listed)
    #expect(got == test.WantCarry)
}
