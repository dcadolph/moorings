import Testing

@testable import MooringsCore

// WatchRetryCase is a number of refused asks and what the retry state says after them.
struct WatchRetryCase: Sendable {
    // Failures is how many asks were refused, one second apart starting at zero.
    var Failures: Int
    // At is the time the state is checked.
    var At: Double
    // WantEager is whether the app is still in its eager tries.
    var WantEager: Bool
    // WantDue is whether the app may be asked at At.
    var WantDue: Bool
}

// watchRetryCases covers the eager tries, the switch to the slow pace and the slow pace itself.
let watchRetryCases: [WatchRetryCase] = [
    // Test 0: An app never asked is eager and due.
    WatchRetryCase(Failures: 0, At: 0, WantEager: true, WantDue: true),
    // Test 1: An app refused once is asked again on the next refresh.
    WatchRetryCase(Failures: 1, At: 1, WantEager: true, WantDue: true),
    // Test 2: The last eager try still leaves it due at once.
    WatchRetryCase(Failures: WatchRetry.tries - 1, At: Double(WatchRetry.tries - 1), WantEager: true, WantDue: true),
    // Test 3: Once the eager tries run out, it stops keeping passes looking and waits.
    WatchRetryCase(Failures: WatchRetry.tries, At: Double(WatchRetry.tries), WantEager: false, WantDue: false),
    // Test 4: It is asked again once the slow pace has passed, never given up for good.
    WatchRetryCase(Failures: WatchRetry.tries, At: Double(WatchRetry.tries - 1) + WatchRetry.slowSeconds,
                   WantEager: false, WantDue: true),
    // Test 5: Refusals on the slow pace keep it on the slow pace.
    WatchRetryCase(Failures: WatchRetry.tries + 3, At: Double(WatchRetry.tries + 3), WantEager: false, WantDue: false),
]

@Test(arguments: watchRetryCases)
func testWatchRetry(test: WatchRetryCase) {
    var retry = WatchRetry()
    for i in 0 ..< test.Failures {
        retry.failed(Double(i))
    }
    #expect(retry.eager == test.WantEager)
    #expect(retry.due(test.At) == test.WantDue)
}
