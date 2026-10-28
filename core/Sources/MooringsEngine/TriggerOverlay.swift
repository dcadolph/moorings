import MooringsCore

// Hold names why a held-key throw or hover may not start.
enum Hold {
    // blocker returns why a hold may not start, or nil when it may.
    static func blocker(_ anchors: Anchors, ready: Bool, shortcutsOn: Bool, buttonDown: Bool) -> String? {
        if anchors.choices.paused {
            return "moorings is paused"
        }
        if !shortcutsOn {
            return "shortcuts are off"
        }
        if !ready {
            return "no Accessibility access"
        }
        if buttonDown {
            return "a mouse button is down"
        }
        return nil
    }
}

// TriggerOverlay throws a window while the overlay's trigger key is held. Moving the pointer picks
// one of 16 targets by direction and distance, and arrow keys pick a span on a keyboard grid. A
// footprint previews the pick, and letting go of the trigger applies it to the window that was
// under the pointer when the trigger went down, else the focused one. Escape, or letting go inside
// the dead zone, does nothing. Nothing runs while the trigger is up: no tick and no grabbed keys.
// The grabbed keys arrive by tag: move-left, move-right, move-up and move-down move the span, the
// grow- tags grow it, return applies it and escape cancels.
public final class TriggerOverlay {
    // tickSeconds is how often the pointer is read while the trigger is held.
    public static let tickSeconds = 1.0 / 60

    // platform reads the windows, the screens and the clock.
    private let platform: Platform
    // anchors holds the choices and the pins.
    private let anchors: Anchors
    // actions works out and applies the picks.
    private let actions: ActionRunner
    // footprint previews the pick.
    private let footprint: any OverlayView
    // gridView draws the keyboard grid.
    private let gridView: any GridView
    // picker is the grid action's picker, put away when a hold starts.
    private let picker: GridPicker
    // ticker reads the pointer while the trigger is held, a scheduler of its own.
    private let ticker: any Scheduler
    // held reports whether the trigger is down.
    private var held = false
    // done reports whether this hold is over: canceled, applied by Return, or without a window.
    private var done = false
    // origin is where the pointer was when the trigger went down, in top-left coordinates.
    private var origin = Point(x: 0, y: 0)
    // target is the window the hold acts on, nil until it is read after the trigger goes down.
    private var target: WindowInfo?
    // pick is the cursor picker's current action, nil inside the dead zone.
    private var pick: String?
    // grid is the keyboard grid's span, nil until a grid key is pressed.
    private var grid: OverlayGrid?
    // area is the area the grid divides, the target's own.
    private var area: Frame?

    // init builds an overlay on platform and anchors that applies picks through actions, previews
    // them on footprint and gridView, and reads the pointer through ticker.
    public init(
        platform: Platform, anchors: Anchors, actions: ActionRunner, footprint: any OverlayView,
        gridView: any GridView, picker: GridPicker, ticker: any Scheduler
    ) {
        self.platform = platform
        self.anchors = anchors
        self.actions = actions
        self.footprint = footprint
        self.gridView = gridView
        self.picker = picker
        self.ticker = ticker
    }

    // flagsChanged starts a hold when m shows the trigger down and ends it when they no longer do.
    // It may run inside the platform's event callback, so it reads no window.
    public func flagsChanged(_ m: Modifiers, at p: Point) {
        let down = anchors.choices.overlay.trigger.held(m)
        if down, !held {
            begin(at: p)
        } else if !down, held {
            end()
        }
    }

    // begin starts a hold at p, grabbing the grid keys, and reads the target on the first tick.
    private func begin(at p: Point) {
        picker.cancel()
        held = true
        done = false
        origin = p
        target = nil
        pick = nil
        grid = nil
        area = nil
        if let why = Hold.blocker(
            anchors, ready: platform.windows.ready, shortcutsOn: platform.keys.shortcutsOn,
            buttonDown: platform.pointer.buttonDown)
        {
            log("overlay: trigger held but \(why): nothing to throw")
            done = true
            return
        }
        _ = platform.keys.grab(Self.gridKeys(anchors.choices.overlay.trigger)) { [weak self] in self?.key($0) }
        ticker.schedule(at: platform.clock.now) { [weak self] in self?.read() }
    }

    // read finds the window the hold acts on, the one under where the trigger went down or else the
    // focused one, then starts the ticks.
    private func read() {
        guard held, !done else { return }
        let scan = platform.windows.scan(platform.screens.current(), full: true)
        let id = platform.windows.hit(origin)
        let w = scan.windows.first { $0.id == id && !$0.isFilePanel } ?? scan.focused
        guard let w, !anchors.pinned(w), !w.isFullScreen else {
            log("overlay: no window to throw under the pointer or in front")
            done = true
            return
        }
        target = w
        tick()
    }

    // end finishes a hold: it applies the grid span when a grid key was used, else the cursor pick.
    // The move runs on the next tick, outside the callback that saw the key go up.
    private func end() {
        let (w, pick, grid, area, done) = (target, pick, grid, area, done)
        held = false
        reset()
        guard !done, let w else { return }
        guard !platform.pointer.buttonDown else {
            log("overlay: trigger let go while a mouse button is down: nothing thrown")
            return
        }
        let gap = anchors.choices.gapPx
        ticker.schedule(at: platform.clock.now) { [weak self] in
            guard let self else { return }
            if let grid, let area {
                actions.applyFrame(grid.frame(area, gap: gap), to: w.id)
            } else if let pick {
                _ = actions.run(pick, window: w.id)
            }
        }
    }

    // reset stops the ticks, lets the grid keys go and hides the preview.
    private func reset() {
        ticker.cancel()
        platform.keys.ungrab()
        footprint.hide()
        gridView.hide()
    }

    // tick reads the pointer and moves the preview when the pick changes, then schedules the next
    // tick. The grid, once used, owns the preview.
    private func tick() {
        guard held, !done else { return }
        ticker.schedule(at: platform.clock.now + Self.tickSeconds) { [weak self] in self?.tick() }
        guard grid == nil, let w = target else { return }
        let loc = platform.pointer.position
        let next = Overlay.pick(dx: loc.x - origin.x, dy: loc.y - origin.y)
        guard next != pick else { return }
        pick = next
        guard let next, let f = actions.frame(next, for: w, screens: platform.screens.current()).0 else {
            footprint.hide()
            return
        }
        footprint.show(f, style: anchors.choices.snapping.footprint, palette: .harbor)
    }

    // key handles a grabbed key by its tag: move or grow the grid span, apply it, or cancel.
    public func key(_ tag: String) {
        guard held, !done else { return }
        switch tag {
        case "escape":
            done = true
            reset()
        case "return":
            guard let grid, let area, let w = target else { return }
            done = true
            reset()
            actions.applyFrame(grid.frame(area, gap: anchors.choices.gapPx), to: w.id)
        default:
            guard let w = target, let step = Self.step(tag) else { return }
            let choices = anchors.choices
            let a = area ?? actions.area(for: w, screens: platform.screens.current())
            var g =
                grid
                ?? OverlayGrid(
                    cols: choices.overlay.gridColumns, rows: choices.overlay.gridRows,
                    at: platform.pointer.position, in: a)
            if grid != nil {
                g = tag.hasPrefix("grow-") ? g.grown(step) : g.moved(step)
            }
            area = a
            grid = g
            pick = nil
            footprint.hide()
            gridView.show(g, in: a, gap: choices.gapPx, style: choices.snapping.footprint, palette: .harbor)
        }
    }

    // log writes why a hold did nothing.
    private func log(_ line: String) {
        platform.log.note(.overlay, line)
    }

    // gridKeys lists the keys a hold of trigger grabs: arrows move the span and Shift-arrows grow it,
    // under the trigger's own modifier, plus Return, Enter and Escape. Fn has no modifier a grab can
    // name, so for Fn the bare keys are grabbed, with Home, End, Page Up and Page Down standing in
    // for the arrows Fn turns into them. The grid action's picker grabs with no trigger.
    public static func gridKeys(_ trigger: OverlayTrigger) -> [GrabKey] {
        let mods: Modifiers =
            switch trigger {
            case .rightOption: .option
            case .rightCommand: .command
            case .rightControl: .control
            case .fn, .none: []
            }
        var arrows = [("left", "left"), ("right", "right"), ("up", "up"), ("down", "down")]
        if trigger == .fn {
            arrows += [("home", "left"), ("end", "right"), ("pageup", "up"), ("pagedown", "down")]
        }
        var out: [GrabKey] = []
        for (key, dir) in arrows {
            out.append(GrabKey(key: key, modifiers: mods, tag: "move-\(dir)"))
            out.append(GrabKey(key: key, modifiers: mods.union(.shift), tag: "grow-\(dir)"))
        }
        for (key, tag) in [("return", "return"), ("enter", "return"), ("escape", "escape")] {
            out.append(GrabKey(key: key, modifiers: mods, tag: tag))
        }
        return out
    }

    // step returns the direction a grid key's tag names.
    public static func step(_ tag: String) -> OverlayStep? {
        switch tag.split(separator: "-").last {
        case "left": .left
        case "right": .right
        case "up": .up
        case "down": .down
        default: nil
        }
    }
}
