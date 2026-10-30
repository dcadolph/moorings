import AppKit
import os

import MooringsCore

// KeyClaim is one claimed key: its virtual key code, the modifiers that must be held with it and
// nothing more, and the tag a press delivers.
struct KeyClaim: Equatable {
    // code is the virtual key code.
    let code: Int
    // modifiers are the side-free modifiers held with it, exactly.
    let modifiers: Modifiers
    // tag is what a press delivers to the claim's handler.
    let tag: String
}

// KeyMatch is what the key tap does with one key down.
enum KeyMatch: Equatable {
    // pass lets the key through to the front app and macOS.
    case pass
    // swallow drops the key and delivers nothing, as for a held key's repeats.
    case swallow
    // deliver drops the key and delivers its tag.
    case deliver(String)
}

// KeyTap is the keyboard event tap behind a claim. It runs only while a claim stands, sees key down
// alone, and swallows exactly the claimed keys with exactly their modifiers, so Control-Left and
// Control-Right walk the channel before macOS moves a Space. Every other key passes untouched. The
// mouse EventTap stays blind to keys.
@MainActor
final class KeyTap {
    // current is the one KeyTap the tap callback reports to.
    nonisolated(unsafe) static weak var current: KeyTap?
    // matched are the side-free modifiers a claim compares; function and the keypad bit that arrows
    // carry are left out.
    nonisolated static let matched: Modifiers = [.shift, .control, .option, .command]

    // logger writes when the tap starts, stops or is turned off by the system.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "keytap")
    // active reports whether a claimed key may be taken now; while it is false every key passes.
    private let active: () -> Bool
    // claims lists the claimed keys, empty when nothing is claimed.
    private var claims: [KeyClaim] = []
    // handler is called with the tag of a claimed press, nil while nothing is claimed.
    private var handler: ((String) -> Void)?
    // port is the tap, nil while nothing is claimed.
    private var port: CFMachPort?
    // source is the tap's run loop source, nil while port is.
    private var source: CFRunLoopSource?
    // disabled counts how often the system turned the tap off.
    private(set) var disabled = 0

    // init builds a key tap that takes claimed keys only while active returns true.
    init(active: @escaping () -> Bool) {
        self.active = active
    }

    // running reports whether the tap is installed and the system has not invalidated it.
    var running: Bool { port.map(CFMachPortIsValid) ?? false }

    // match returns what the tap does with a key down of code with flags against claims: a claimed
    // key with exactly its modifiers is delivered, or swallowed when it is a repeat, and anything else
    // passes.
    nonisolated static func match(_ claims: [KeyClaim], code: Int, flags: CGEventFlags, repeating: Bool) -> KeyMatch {
        let held = Modifiers(flags: flags).intersection(matched)
        guard let c = claims.first(where: { $0.code == code && $0.modifiers.intersection(matched) == held })
        else { return .pass }
        return repeating ? .swallow : .deliver(c.tag)
    }

    // claim replaces the claim with keys and handler, starts the tap, and returns how many keys it
    // took: none when a key has no code or the tap cannot start, as without Accessibility.
    func claim(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        claims = keys.compactMap { k in
            Hotkeys.keyCodes[k.key].map { KeyClaim(code: $0, modifiers: k.modifiers, tag: k.tag) }
        }
        self.handler = handler
        guard !claims.isEmpty, start() else {
            logger.notice("the key tap could not start: nothing claimed")
            unclaim()
            return 0
        }
        return claims.count
    }

    // unclaim lets every claimed key go and removes the tap.
    func unclaim() {
        claims = []
        handler = nil
        stop()
    }

    // start installs the tap on the main run loop and reports whether it is running.
    private func start() -> Bool {
        if running {
            return true
        }
        stop()
        Self.current = self
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let keep = MainActor.assumeIsolated { KeyTap.current?.handle(type, event) ?? true }
            return keep ? Unmanaged.passUnretained(event) : nil
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback,
                userInfo: nil)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        port = tap
        self.source = source
        logger.notice("the key tap started")
        return true
    }

    // stop removes the tap.
    private func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
        logger.notice("the key tap stopped")
    }

    // handle decides one event and returns false to swallow it. A delivered tag runs on the next
    // turn of the main queue, after the tap has returned.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            disabled += 1
            logger.notice("the key tap was turned off by the system (\(self.disabled) times): turning it back on")
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return true
        case .keyDown:
            guard active() else { return true }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            switch Self.match(claims, code: code, flags: event.flags, repeating: repeating) {
            case .pass:
                return true
            case .swallow:
                return false
            case let .deliver(tag):
                if let handler {
                    DispatchQueue.main.async { handler(tag) }
                }
                return false
            }
        default:
            return true
        }
    }
}
