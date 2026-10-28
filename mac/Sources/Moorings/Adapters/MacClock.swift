import Foundation

import MooringsEngine

// MacClock is the Mac Clock: seconds since boot, the clock the delegate's own timestamps use.
final class MacClock: Clock {
    // now is the system uptime in seconds.
    var now: Double { ProcessInfo.processInfo.systemUptime }
}
