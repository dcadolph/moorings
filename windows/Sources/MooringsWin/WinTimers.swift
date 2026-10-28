import WinSDK

import MooringsEngine

// WinTimers is the Windows Timers: each scheduler is its own thread timer, and the message loop hands
// every WM_TIMER to fire, which finds the scheduler it belongs to.
final class WinTimers: Timers {
    // Held keeps a scheduler without owning it, so one its engine object dropped goes away.
    private struct Held {
        // scheduler is the scheduler, nil once it is gone.
        weak var scheduler: WinScheduler?
    }

    // held lists the schedulers handed out.
    private var held: [Held] = []

    // make returns a new WinScheduler whose timer fire runs.
    func make() -> WinScheduler {
        let s = WinScheduler()
        held = held.filter { $0.scheduler != nil } + [Held(scheduler: s)]
        return s
    }

    // scheduler returns a new, independent scheduler.
    func scheduler() -> any Scheduler {
        make()
    }

    // fire runs the work of the scheduler whose timer is id and reports whether one owned it.
    func fire(_ id: UINT_PTR) -> Bool {
        for h in held {
            if let s = h.scheduler, s.fire(id) {
                return true
            }
        }
        return false
    }
}
