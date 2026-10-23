import AppKit
import os

// EventTap is moorings' one mouse event tap. It watches the primary button going down, dragging
// and coming up, and swallows both halves of a click that moorings handles, such as a green
// button click it turns into a lift or a fill.
@MainActor
final class EventTap {
    // current is the one EventTap the tap callback reports to.
    nonisolated(unsafe) static weak var current: EventTap?

    // logger writes when the system turns the tap off.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "tap")
    // onDown is asked about each press with its point and whether Option is held, and returns true
    // to swallow the click.
    var onDown: (CGPoint, Bool) -> Bool = { _, _ in false }
    // onDrag is told where the mouse is while the primary button is held, and whether Option is held.
    var onDrag: (CGPoint, Bool) -> Void = { _, _ in }
    // onUp is told where the primary button came up, for a click that was not swallowed.
    var onUp: (CGPoint, Bool) -> Void = { _, _ in }
    // port is the tap, nil until it starts.
    private var port: CFMachPort?
    // swallowUp reports whether the next button up belongs to a swallowed press.
    private var swallowUp = false
    // disabled counts how often the system turned the tap off.
    private(set) var disabled = 0

    // running reports whether the tap is installed.
    var running: Bool { port != nil }

    // start installs the tap on the main run loop and reports whether it is running. It fails
    // without Accessibility access.
    @discardableResult
    func start() -> Bool {
        if port != nil {
            return true
        }
        Self.current = self
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
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
        return true
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
            return true
        case .leftMouseDown:
            if onDown(event.location, option) {
                swallowUp = true
                return false
            }
            return true
        case .leftMouseUp:
            if swallowUp {
                swallowUp = false
                return false
            }
            onUp(event.location, option)
            return true
        case .leftMouseDragged:
            onDrag(event.location, option)
            return true
        default:
            return true
        }
    }
}
