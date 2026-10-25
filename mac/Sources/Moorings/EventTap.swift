import AppKit
import os

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
    // onDoubleClick is told where the primary button came up to end a double-click that was not
    // swallowed.
    var onDoubleClick: (CGPoint) -> Void = { _ in }
    // onOther is asked about each extra mouse button press or release with the button number and
    // whether it went down, and returns true to swallow it.
    var onOther: (Int, Bool) -> Bool = { _, _ in false }
    // onFlags is told the modifiers held and where the pointer is each time a modifier key goes down
    // or up. It must return at once and never read a window.
    var onFlags: (CGEventFlags, CGPoint) -> Void = { _, _ in }
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
            if onDown(event.location, event.flags) {
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
}
