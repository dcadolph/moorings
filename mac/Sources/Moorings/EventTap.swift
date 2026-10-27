import AppKit
import os

import MooringsCore

// EventTap is moorings' one mouse event tap. It watches the primary button going down, dragging
// and coming up, and swallows both halves of a click that moorings handles, such as a green
// button click it turns into a lift or a fill. It also sees modifier keys change, for the
// overlay's trigger key, and never sees other keys.
@MainActor
final class EventTap {
    // current is the one EventTap the tap callback reports to.
    nonisolated(unsafe) static weak var current: EventTap?

    // logger writes when the system turns the tap off.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "tap")
    // onDown is asked about each press with its point and the modifiers held, and returns true to
    // swallow the click.
    var onDown: (CGPoint, CGEventFlags) -> Bool = { _, _ in false }
    // onDrag is told where the mouse is while the primary button is held, and which modifiers are held.
    var onDrag: (CGPoint, CGEventFlags) -> Void = { _, _ in }
    // onUp is told where the primary button came up, for a click that was not swallowed.
    var onUp: (CGPoint, Bool) -> Void = { _, _ in }
    // onSwallowedUp is told where the primary button came up to end a press that was swallowed.
    var onSwallowedUp: (CGPoint) -> Void = { _ in }
    // onDoubleClick is told where the primary button came up to end a double-click that was not
    // swallowed.
    var onDoubleClick: (CGPoint) -> Void = { _ in }
    // onOther is asked about each extra mouse button press or release with the button number and
    // whether it went down, and returns true to swallow it.
    var onOther: (Int, Bool) -> Bool = { _, _ in false }
    // onFlags is told the modifiers held and where the pointer is each time a modifier key goes down
    // or up. It must return at once and never read a window.
    var onFlags: (CGEventFlags, CGPoint) -> Void = { _, _ in }
    // port is the tap, nil until it starts and after it stops.
    private var port: CFMachPort?
    // source is the tap's run loop source, nil while port is.
    private var source: CFRunLoopSource?
    // press is the primary button's state as the tap saw it.
    private var press = TapPress()
    // disabled counts how often the system turned the tap off.
    private(set) var disabled = 0

    // running reports whether the tap is installed and the system has not invalidated it.
    var running: Bool { port.map(CFMachPortIsValid) ?? false }

    // start installs the tap on the main run loop and reports whether it is running. A tap the
    // system invalidated is torn down and made again. It fails without Accessibility access.
    @discardableResult
    func start() -> Bool {
        if running {
            return true
        }
        stop()
        Self.current = self
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let keep = MainActor.assumeIsolated { EventTap.current?.handle(type, event) ?? true }
            return keep ? Unmanaged.passUnretained(event) : nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        port = tap
        self.source = source
        return true
    }

    // stop removes the tap, as when Accessibility is turned off, and ends a press and any held
    // modifiers it would otherwise never see released.
    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
        resync(released: true)
    }

    // handle routes one event and returns false to swallow it.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let option = event.flags.contains(.maskAlternate)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            disabled += 1
            logger.notice("the mouse tap was turned off by the system (\(self.disabled) times): turning it back on")
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            resync()
            return true
        case .leftMouseDown:
            if press.pressing() == .swallowed {
                onSwallowedUp(event.location)
            }
            let swallow = onDown(event.location, event.flags)
            press.down(swallow: swallow)
            return !swallow
        case .leftMouseUp:
            if press.up() == .swallowed {
                onSwallowedUp(event.location)
                return false
            }
            onUp(event.location, option)
            if event.getIntegerValueField(.mouseEventClickState) == 2 {
                onDoubleClick(event.location)
            }
            return true
        case .leftMouseDragged:
            onDrag(event.location, event.flags)
            return true
        case .flagsChanged:
            onFlags(event.flags, event.location)
            return true
        case .otherMouseDown, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return !onOther(button, type == .otherMouseDown)
        default:
            return true
        }
    }

    // resync ends a press whose release came while the system had the tap off and tells the
    // handlers which modifiers are held now, so no swallowed release, drag or trigger key is left
    // waiting for an event the tap never saw. With released set, as when the tap stops, it treats
    // the button as up and no modifier as held.
    private func resync(released: Bool = false) {
        let at = CGEvent(source: nil)?.location ?? .zero
        let down = !released && CGEventSource.buttonState(.combinedSessionState, button: .left)
        switch press.recover(buttonDown: down) {
        case .swallowed: onSwallowedUp(at)
        case .plain: onUp(at, false)
        case .none: break
        }
        onFlags(released ? [] : CGEventSource.flagsState(.combinedSessionState), at)
    }
}

// EdgeResizer moves the edge two windows share for both of them, as a divider between panes does,
// when a drag starts on it with the edge resize keys held. Moves are applied once per run loop turn
// so a fast drag never backs up the tap.
@MainActor
final class EdgeResizer {
    // Drag is a shared edge being moved: the two windows, their frames at the press, which way the
    // edge runs, and where the press was.
    struct Drag {
        // a is the window left of or above the edge.
        let a: WindowID
        // b is the window right of or below the edge.
        let b: WindowID
        // fa is a's frame at the press.
        let fa: Frame
        // fb is b's frame at the press.
        let fb: Frame
        // vertical reports whether the edge runs top to bottom.
        let vertical: Bool
        // start is where the press was.
        let start: CGPoint
    }

    // app is the running app delegate.
    private unowned let app: AppDelegate
    // drag is the edge being moved, nil when none is.
    private var drag: Drag?
    // latest is the pointer's last place in the drag, nil once applied.
    private var latest: CGPoint?

    // init builds an edge resizer for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // active reports whether a shared edge is being moved.
    var active: Bool { drag != nil }

    // pressed starts moving the shared edge under p when the edge resize keys are exactly the
    // modifiers in flags, and reports whether it did, so the press is swallowed. Anchored, stashed,
    // fullscreen windows and file panels never take part.
    func pressed(_ p: CGPoint, flags: CGEventFlags) -> Bool {
        let anchors = app.anchors
        guard !anchors.choices.paused, Hover.holds(flags.rawValue, anchors.choices.overlay.edgeResize) else { return false }
        let scan = app.windows.scan(Screens.current())
        let pool = scan.windows.filter {
            !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0) && !anchors.stashed.contains($0.id)
        }
        guard let e = SharedEdges.find(at: Point(x: p.x, y: p.y), frames: pool.map(\.frame)) else { return false }
        let a = pool[e.a]
        let b = pool[e.b]
        anchors.save(a)
        anchors.save(b)
        drag = Drag(a: a.id, b: b.id, fa: a.frame, fb: b.frame, vertical: e.vertical, start: p)
        return true
    }

    // dragged notes the pointer's place and applies it on the next run loop turn.
    func dragged(_ p: CGPoint) {
        guard drag != nil else { return }
        let waiting = latest != nil
        latest = p
        if !waiting {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }
    }

    // apply moves both windows for the pointer's last place.
    private func apply() {
        guard let d = drag, let p = latest else { return }
        latest = nil
        let delta = d.vertical ? p.x - d.start.x : p.y - d.start.y
        let (fa, fb) = SharedEdges.resize(d.fa, d.fb, vertical: d.vertical, delta: delta)
        app.windows.move(d.a, to: fa)
        app.windows.move(d.b, to: fb)
    }

    // released applies the last place and ends the drag on the next main queue turn, outside the tap
    // callback that saw the button come up.
    func released() {
        guard drag != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            apply()
            drag = nil
            app.tiler.mouseUp()
            app.wake()
        }
    }
}
