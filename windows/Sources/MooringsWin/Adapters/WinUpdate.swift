import Foundation
import Synchronization

import MooringsCore

// WinUpdate looks for a newer release on GitHub on the core's schedule and keeps the one it found for
// the tray. The request runs off the main thread, and ended is called on that thread when a check
// finishes, found or failed, so the caller can hand the news back to its message loop.
final class WinUpdate: Sendable {
    // Check is what the last check left: when it started, the release it found, and whether one is
    // still running.
    struct Check {
        // checked is when the last check started, nil before the first.
        var checked: Date?
        // found is the newer release the last check that succeeded named, nil when there is none.
        var found: ReleaseInfo?
        // running is true while a request is out.
        var running = false
    }

    // checker asks GitHub.
    let checker: UpdateChecker
    // launched is when the app started, which the first check waits on.
    let launched: Date
    // ended runs on the checking thread when a check finishes, with the release found or the error.
    let ended: @Sendable (Result<ReleaseInfo?, any Error>) -> Void
    // state holds what the last check left.
    private let state = Mutex(Check())

    // init builds an updater for checker, started at launched, that tells ended about every check.
    init(
        checker: UpdateChecker, launched: Date = Date(),
        ended: @escaping @Sendable (Result<ReleaseInfo?, any Error>) -> Void
    ) {
        self.checker = checker
        self.launched = launched
        self.ended = ended
    }

    // found is the newer release the last successful check named.
    var found: ReleaseInfo? {
        state.withLock { $0.found }
    }

    // due reports whether a check should start at now: none is running and the last one is stale.
    func due(now: Date = Date()) -> Bool {
        state.withLock { !$0.running && UpdateSchedule.isDue(lastChecked: $0.checked, launched: launched, now: now) }
    }

    // start sends a check off the main thread unless one is running. A failed check keeps the release
    // found before, so a lost connection never hides an update the tray already shows.
    func start(now: Date = Date()) {
        let go = state.withLock { s in
            guard !s.running else { return false }
            s.running = true
            s.checked = now
            return true
        }
        guard go else { return }
        Task.detached { [self] in
            let result: Result<ReleaseInfo?, any Error>
            do {
                result = .success(try await checker.check())
            } catch {
                result = .failure(error)
            }
            state.withLock { s in
                s.running = false
                if case .success(let found) = result {
                    s.found = found
                }
            }
            ended(result)
        }
    }
}
