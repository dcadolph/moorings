import MooringsCore
import MooringsEngine

extension AppDelegate {
    // macPlatform builds the Platform from the Mac adapters, the only place every adapter is named.
    // A save shows the choices the menu bar icon, the ignore list and the anchor hint read.
    func macPlatform() -> Platform {
        Platform(
            windows: windows, screens: MacScreens(), overlay: Footprint(haptic: true),
            notifier: MacNotifier { [unowned self] in self.notify($0, $1) },
            clock: MacClock(),
            store: DefaultsStore(key: Self.choicesKey) { [unowned self] _ in
                showIcon()
                refreshShortcuts()
                hintAnchor(Screens.current())
            },
            pointer: pointer, keys: keys, apps: apps, log: log, timers: timers, events: events,
            grid: GridPanel(), badge: badge
        )
    }
}
