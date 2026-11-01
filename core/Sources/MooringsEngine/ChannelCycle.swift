import MooringsCore

// ChannelCycle claims Control-Left and Control-Right while the front window fills the channel, so
// they walk the channel's windows the way they walk native fullscreen apps, and lets them go back to
// the platform at any other time. Every pass, every action and every green button click syncs it, so
// the Mac and Windows roots share one decision.
public final class ChannelCycle {
    // keys are the keys a claim takes: Control-Left walks back and Control-Right walks on.
    public static let keys = [
        GrabKey(key: "left", modifiers: .control, tag: "cycle-channel-windows-backward"),
        GrabKey(key: "right", modifiers: .control, tag: "cycle-channel-windows"),
    ]

    // engine routes a claimed press to the organizer.
    unowned let engine: Engine
    // platform reads the windows and holds the keys.
    private let platform: Platform
    // anchors holds the choices the claim follows.
    private let anchors: Anchors
    // claimed reports whether the keys are claimed now.
    public private(set) var claimed = false

    // init builds a channel cycle on engine's platform and anchors, with nothing claimed.
    public init(engine: Engine, platform: Platform, anchors: Anchors) {
        self.engine = engine
        self.platform = platform
        self.anchors = anchors
    }

    // wanted reports whether the keys belong to the channel for scan on screens: the root declares
    // the channel cycle, the switch is on, nothing is paused, the shortcuts are on, the organize
    // actions run here, an ultrawide is attached and the focused window fills the channel.
    func wanted(_ scan: Scan, screens: Screens) -> Bool {
        guard engine.features.contains(.channelCycle), anchors.choices.channelCycle, !anchors.choices.paused,
            platform.keys.shortcutsOn,
            engine.offers(Self.keys[1].tag), screens.ultrawide != nil, let w = scan.focused
        else { return false }
        return engine.actions.fills(w, screens: screens)
    }

    // sync claims the keys when scan on screens wants them and lets them go when it does not. It
    // calls the platform only on a change, so passes do not churn the keys.
    public func sync(_ scan: Scan, screens: Screens) {
        let want = wanted(scan, screens: screens)
        guard want != claimed else { return }
        if want {
            let taken = platform.keys.claim(Self.keys) { [unowned self] tag in
                _ = engine.route(tag, window: nil)
            }
            claimed = true
            platform.log.note(.actions, "channel cycle: claimed \(taken) keys")
        } else {
            unclaim()
        }
    }

    // sync reads the windows now and syncs on them, for the actions and clicks that change the front
    // window between passes.
    public func sync() {
        guard platform.windows.ready else {
            unclaim()
            return
        }
        let screens = platform.screens.current()
        sync(platform.windows.scan(screens, full: false), screens: screens)
    }

    // unclaim lets the keys go back to the platform when they are claimed.
    public func unclaim() {
        guard claimed else { return }
        platform.keys.unclaim()
        claimed = false
        platform.log.note(.actions, "channel cycle: let the keys go")
    }
}
