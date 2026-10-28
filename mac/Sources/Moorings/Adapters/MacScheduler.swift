import Foundation

import MooringsEngine

// MacScheduler is the Mac Scheduler: one main run loop timer, replaced on each schedule.
@MainActor
final class MacScheduler: @preconcurrency Scheduler {
    // timer is the pending timer, nil when nothing is pending.
    private var timer: Timer?
    // work is the pending work, nil when nothing is pending.
    private var work: (() -> Void)?

    // schedule runs work at uptime at on the main thread, replacing any pending work.
    func schedule(at: Double, _ work: @escaping () -> Void) {
        timer?.invalidate()
        self.work = work
        let wait = max(0, at - ProcessInfo.processInfo.systemUptime)
        timer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    // cancel drops the pending work.
    func cancel() {
        timer?.invalidate()
        timer = nil
        work = nil
    }

    // fire runs the pending work once, clearing it first so the work may schedule more.
    private func fire() {
        let w = work
        timer = nil
        work = nil
        w?()
    }
}
