import MooringsCore

// PlatformActions runs the actions only a platform has: the menu and the strip editor. It answers
// handles without running, so supports and the shortcut tables can ask it.
public protocol PlatformActions: AnyObject {
    // handles reports whether the platform runs action name.
    func handles(_ name: String) -> Bool
    // run runs action name on a window, the focused one when nil, and reports whether it acted.
    func run(_ name: String, window: WindowID?) -> Bool
}

// NoPlatformActions is the PlatformActions of a platform with none: Windows until it has a menu
// action, and the tests.
public final class NoPlatformActions: PlatformActions {
    // init builds it.
    public init() {}

    // handles is always false.
    public func handles(_ name: String) -> Bool {
        false
    }

    // run is always false.
    public func run(_ name: String, window: WindowID?) -> Bool {
        false
    }
}

// ThrowViews are the views a throw overlay draws on: a footprint and a grid that lets clicks
// through, separate from the drag footprint and the grid that takes the mouse where a platform
// has both.
public struct ThrowViews {
    // footprint shows where the throw lands.
    public var footprint: any OverlayView
    // grid draws the throw's keyboard grid.
    public var grid: any GridView

    // init builds the pair.
    public init(footprint: any OverlayView, grid: any GridView) {
        self.footprint = footprint
        self.grid = grid
    }
}

// Engine is the composition root of the engine: it builds every engine object on one Platform,
// wires them to each other, and carries the orchestration they call: wake, moor, save, landed,
// prune. Engine is plain and non-Sendable, like the objects it holds.
public final class Engine {
    // Features lists the routed actions a platform carries. The root declares them; the Engine
    // runs a routed action only when its feature is declared, and supports reports the same.
    public struct Features: OptionSet, Sendable {
        // rawValue holds one bit per feature.
        public let rawValue: UInt8

        // init builds a set from its bits.
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        // grid is the grid action: the platform's GridView draws and takes the mouse.
        public static let grid = Features(rawValue: 1 << 0)
        // stash is the stash actions and the drop at an edge: the platform's Pointer tracks.
        public static let stash = Features(rawValue: 1 << 1)
        // organize is the tile, cascade, cycle, mirror, tidy and undo actions.
        public static let organize = Features(rawValue: 1 << 2)
        // tiling is the tiling modes.
        public static let tiling = Features(rawValue: 1 << 3)
        // workspaces is saving and recalling workspaces and the app rules.
        public static let workspaces = Features(rawValue: 1 << 4)
        // profiles is switching profiles.
        public static let profiles = Features(rawValue: 1 << 5)
        // badge is the stack badge: the platform's BadgeView draws.
        public static let badge = Features(rawValue: 1 << 6)
        // all is every feature, what the Mac declares.
        public static let all: Features = [.grid, .stash, .organize, .tiling, .workspaces, .profiles, .badge]
    }

    // Observers is what the tests, the probes and the selftest watch. Every field defaults to
    // nothing.
    public struct Observers {
        // moved is told each move a pass applied, the time and where the window read back.
        public var moved: ((Move, Double, Frame?) -> Void)?
        // released is told each pin the owner moved by hand, and the time.
        public var released: (WindowID, Double) -> Void = { _, _ in }
        // passed is told the time of each pass and how many moves it made.
        public var passed: (Double, Int) -> Void = { _, _ in }
        // noticed is told each window event the engine handled, and the time.
        public var noticed: (WindowEvent, Double) -> Void = { _, _ in }
        // showed is told each footprint shown for a new zone and its style.
        public var showed: (Frame, FootprintStyle) -> Void = { _, _ in }
        // dropped is told the window and what it dropped on at the end of each drag that moved one.
        public var dropped: (WindowID, SnapDrop?) -> Void = { _, _ in }

        // init builds observers that watch nothing.
        public init() {}
    }

    // platform is what the engine reads and drives.
    public let platform: Platform
    // anchors holds the layout and decides every move, loaded from the platform's store.
    public let anchors: Anchors
    // features lists the routed actions this platform carries.
    public let features: Features
    // platformActions runs the menu and the strip editor where the platform has them.
    public let platformActions: any PlatformActions
    // observers is what the tests and probes watch.
    public var observers = Observers()
    // throwViews are the footprint and click-through grid the throw overlay draws on.
    public let throwViews: ThrowViews
    // wasReady is whether the window store could act at the last look, to catch a grant or a loss.
    private var wasReady: Bool
    // fallback is why the choices init loaded are the defaults, nil when they are the saved ones;
    // start logs it once.
    private var fallback: String?

    // actions applies window actions to the focused window.
    public private(set) lazy var actions = ActionRunner(engine: self, platform: platform, anchors: anchors)
    // organizer lays out several windows at once.
    public private(set) lazy var organizer = Organizer(engine: self, platform: platform, anchors: anchors)
    // workspaces saves and recalls workspaces, applies app rules and switches profiles.
    public private(set) lazy var workspaces = WorkspaceKeeper(
        engine: self, platform: platform, anchors: anchors, organizer: organizer, actions: actions)
    // tiler keeps free windows in the tiling mode's layout.
    public private(set) lazy var tiler = Tiler(engine: self, platform: platform, anchors: anchors, organizer: organizer)
    // stasher parks windows at a screen edge.
    public private(set) lazy var stasher = Stasher(
        engine: self, platform: platform, anchors: anchors, rest: platform.timers.scheduler())
    // gridPicker pops a grid of cells for the grid actions.
    public private(set) lazy var gridPicker = GridPicker(platform: platform, anchors: anchors, actions: actions)
    // overlay throws a window while the overlay's trigger key is held.
    public private(set) lazy var overlay = TriggerOverlay(
        platform: platform, anchors: anchors, actions: actions, footprint: throwViews.footprint,
        gridView: throwViews.grid, picker: gridPicker, ticker: platform.timers.scheduler())
    // hover moves or resizes the window under the pointer while the hover modifiers are held.
    public private(set) lazy var hover = HoverMover(
        engine: self, platform: platform, anchors: anchors, ticker: platform.timers.scheduler())
    // drag follows a window dragged by its frame and runs its drop.
    public private(set) lazy var drag = DragFollower(engine: self, platform: platform, anchors: anchors)
    // passes run the window passes.
    public private(set) lazy var passes = PassLoop(
        engine: self, platform: platform, anchors: anchors, workspaces: workspaces)
    // badge counts the stacked windows under a resting pointer.
    public private(set) lazy var badge = StackBadge(engine: self, platform: platform, anchors: anchors)
    // channelCycle claims Control-Left and Control-Right while the front window fills the channel.
    public private(set) lazy var channelCycle = ChannelCycle(engine: self, platform: platform, anchors: anchors)

    // init builds every engine object on platform, in the order above, with the routed actions in
    // features and the platform's own actions in platformActions. The throw draws on throwViews,
    // the platform's overlay and grid unless the root gives it views of its own.
    public init(
        platform: Platform, features: Features, platformActions: any PlatformActions = NoPlatformActions(),
        throwViews: ThrowViews? = nil
    ) {
        self.platform = platform
        self.features = features
        self.platformActions = platformActions
        self.throwViews = throwViews ?? ThrowViews(footprint: platform.overlay, grid: platform.grid)
        let loaded = platform.store.load()
        anchors = Anchors(choices: loaded.choices)
        fallback = loaded.fallback
        wasReady = platform.windows.ready
        _ = actions
        _ = organizer
        _ = workspaces
        _ = tiler
        _ = stasher
        _ = gridPicker
        _ = overlay
        _ = hover
        _ = drag
        _ = passes
        _ = badge
        _ = channelCycle
    }

    // start marks the launch, starts the events when the window store can act, binds the shortcuts,
    // starts the badge when it is on, and runs the first pass. The roots call it once; the probes do
    // not.
    public func start() {
        if let fallback {
            platform.log.note(.choices, "choices fell back to the defaults: \(fallback)")
            self.fallback = nil
        }
        anchors.launch(now: platform.clock.now)
        wasReady = platform.windows.ready
        if wasReady {
            listen()
        }
        bind()
        badge.sync()
        passes.wake()
        passes.moor()
    }

    // mouseHeld reports whether the owner holds a window: the primary button, a hover that holds one,
    // or a drag under way.
    public var mouseHeld: Bool {
        platform.pointer.primaryDown || hover.active || drag.following
    }

    // wake marks windows as changing, so passes run until they settle and read every app.
    public func wake() {
        passes.wake()
    }

    // moor runs a pass now.
    public func moor() {
        passes.moor()
    }

    // landed records frame as where an action just read the window with id back after moving it,
    // so the pass after reads it at rest, and runs passes until the windows settle without reading
    // every app.
    public func landed(_ id: WindowID, at frame: Frame) {
        passes.landed(id, at: frame)
        passes.wake(full: false)
    }

    // save writes the choices to the store, binds the shortcuts again, and runs a pass so the change
    // shows at once. A store that cannot write logs under .choices and the choices stay in effect.
    public func save() {
        do {
            try platform.store.save(anchors.choices)
        } catch {
            platform.log.note(.choices, "choices not saved: \(error)")
        }
        settle()
    }

    // shutdown lets the claimed keys go, puts every stashed window back and clears the pending
    // pass. Both roots run it from Quit, so no key stays claimed and no window is left parked off
    // screen.
    public func shutdown() {
        channelCycle.unclaim()
        stasher.unstashAll()
        passes.stop()
    }

    // reload re-reads the choices from the store and binds the shortcuts again.
    public func reload() {
        load()
        settle()
    }

    // load re-reads the choices from the store and logs that it did, and why when they fell back to
    // the defaults.
    private func load() {
        let loaded = platform.store.load()
        anchors.choices = loaded.choices
        if let fallback = loaded.fallback {
            platform.log.note(.choices, "choices fell back to the defaults: \(fallback)")
        }
        platform.log.note(.choices, "choices reloaded")
    }

    // settle follows a change of the choices: the shortcuts, the badge and a pass.
    private func settle() {
        bind()
        badge.sync()
        passes.wake()
        passes.moor()
    }

    // beforePass runs before each pass: it starts or stops the events when Accessibility changed and
    // reloads the choices when the store says they moved. The pass about to run shows the reload.
    public func beforePass() {
        let ready = platform.windows.ready
        if ready != wasReady {
            wasReady = ready
            if ready {
                platform.log.note(.passes, "the window store can act: starting the events")
                listen()
                platform.notifier.notify(
                    "Moorings is ready", "Accessibility is on. Anchored apps take their slots now.")
            } else {
                platform.log.note(.passes, "the window store cannot act: stopping the events")
                platform.events.stop()
                channelCycle.unclaim()
            }
        }
        if platform.store.changed() {
            load()
            bind()
            badge.sync()
            passes.wake()
        }
    }

    // listen starts the platform's events, each handled on the engine's thread. start calls it; a
    // probe that runs passes without start calls it to hear the events.
    public func listen() {
        platform.events.start { [unowned self] in handle($0) }
    }

    // handle wakes the passes for one window event and keeps what the event changes: the displays,
    // and the launch window that reads every app while a new app shows its first window. An event
    // that names its window wakes narrow, since the source marked that window's app.
    public func handle(_ event: WindowEvent) {
        let t = platform.clock.now
        observers.noticed(event, t)
        switch event {
        case .moved, .shown, .destroyed, .focused:
            passes.wake(full: false)
        case .appLaunched:
            passes.launching = t + Pace.launchSeconds
            passes.wake()
        case .screensChanged:
            anchors.screensChanged()
            workspaces.screensChanged()
            passes.wake()
        case .appQuit, .wake:
            passes.wake()
        }
    }

    // bind registers every shortcut in effect that this platform supports and logs the problems
    // with the saved ones under .choices.
    private func bind() {
        let bindings = Bindings(anchors.choices)
        for p in bindings.problems {
            platform.log.note(.choices, p)
        }
        platform.keys.bind(bindings.map.filter { actions.supports($0.key) })
    }

    // passed runs the engine's part of each pass after the moves: the workspaces, the tiler and the
    // channel cycle's claim.
    public func passed(_ scan: Scan, _ screens: Screens, _ held: Bool) {
        workspaces.seen(scan.windows, screens: screens)
        tiler.pass(scan.windows, screens: screens, mouseHeld: held)
        channelCycle.sync(scan, screens: screens)
    }

    // prune forgets the windows that are gone: the actions' last presses and the stashes.
    public func prune(alive: Set<WindowID>) {
        actions.prune(alive: alive)
        stasher.prune(alive: alive)
    }

    // offers reports whether the engine can run routed action name on this platform: the menu and
    // strips when platformActions handles them, and the rest when their feature is declared.
    public func offers(_ name: String) -> Bool {
        if name == Keymaps.menuName || name == Keymaps.stripsName {
            return platformActions.handles(name)
        }
        return feature(name).map(features.contains) ?? false
    }

    // feature returns the feature routed action name needs, nil for a name no feature routes.
    private func feature(_ name: String) -> Features? {
        if Overlay.gridSize(name, anchors.choices.overlay) != nil {
            return .grid
        }
        if Keymaps.stashNames.contains(name) {
            return .stash
        }
        if Tile.handles(name) {
            return .organize
        }
        if Tiling.handles(name) {
            return .tiling
        }
        if name.hasPrefix(Keymaps.workspacePrefix) {
            return .workspaces
        }
        if name.hasPrefix(Profile.prefix) {
            return .profiles
        }
        return nil
    }

    // route runs routed action name on a window, the focused one when nil, through the object that
    // owns it, and reports whether it acted. A name this platform does not offer logs under .actions
    // and returns false.
    public func route(_ name: String, window: WindowID?) -> Bool {
        guard offers(name) else {
            platform.log.note(.actions, "\(name): not on this platform yet")
            return false
        }
        if name == Keymaps.menuName || name == Keymaps.stripsName {
            return platformActions.run(name, window: window)
        }
        if let size = Overlay.gridSize(name, anchors.choices.overlay) {
            return gridPicker.show(cols: size.cols, rows: size.rows, window: window)
        }
        if Keymaps.stashNames.contains(name) {
            return stasher.run(name)
        }
        if Tile.handles(name) {
            return organizer.run(name)
        }
        if Tiling.handles(name) {
            return tiler.run(name)
        }
        if name.hasPrefix(Keymaps.workspacePrefix) {
            return workspaces.recall(String(name.dropFirst(Keymaps.workspacePrefix.count)))
        }
        let title = String(name.dropFirst(Profile.prefix.count))
        guard anchors.choices.profiles.contains(where: { $0.name == title }) else { return false }
        return workspaces.applyProfile(title)
    }

    // stashEdge returns the edge a drag ending at p with the held keys stashes at, nil when the
    // platform has no stash or the drop is not at an edge.
    public func stashEdge(_ p: Point, held: Modifiers) -> StashEdge? {
        guard features.contains(.stash) else { return nil }
        return stasher.dropEdge(p, held: held)
    }

    // stash parks w at edge to come back to original, where the platform has a stash.
    public func stash(_ w: WindowInfo, edge: StashEdge, original: Frame?) {
        guard features.contains(.stash) else { return }
        stasher.stash(w, edge: edge, original: original)
    }
}
