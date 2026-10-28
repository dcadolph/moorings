// WatchRetry decides when to ask again an app that refused its window observer, as an app still
// starting up does. It asks on every refresh at first, then every slowSeconds for as long as the app
// runs, so an app that takes long to start is still watched once it is ready.
public struct WatchRetry: Equatable, Sendable {
    // tries is how many refreshes in a row ask again before the slow pace starts.
    public static let tries = 20
    // slowSeconds is how long the slow pace waits between asks.
    public static let slowSeconds = 10.0

    // left is how many eager tries remain.
    public private(set) var left = tries
    // next is the earliest time the app is asked again.
    public private(set) var next = 0.0

    // init makes the retry state of an app not yet asked.
    public init() {}

    // eager reports whether the app is still in its eager tries, which keep passes looking for it.
    public var eager: Bool { left > 0 }

    // due reports whether the app may be asked again at now.
    public func due(_ now: Double) -> Bool {
        now >= next
    }

    // failed records an ask at now that the app refused.
    public mutating func failed(_ now: Double) {
        if left > 0 {
            left -= 1
        }
        next = left > 0 ? now : now + Self.slowSeconds
    }
}
