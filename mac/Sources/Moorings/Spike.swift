import AppKit
import ApplicationServices
import os

// Spike runs the step 0 checks: Accessibility, window listing and moves, and an event tap that sees
// drags and swallows a green button click. Each result goes to the unified log under the
// com.dcadolph.moorings subsystem so a shell can read it with `log show`.
@MainActor
final class Spike {
    // Command names one check, reachable from the menu, a moorings:// link, or `--spike` at launch.
    enum Command: String, CaseIterable {
        case status, prompt, list, move, tap, untap, quit

        // title is the menu item label.
        var title: String {
            switch self {
            case .status: "Log status"
            case .prompt: "Ask for Accessibility"
            case .list: "List windows"
            case .move: "Move a TextEdit window"
            case .tap: "Start event tap"
            case .untap: "Stop event tap"
            case .quit: "Quit"
            }
        }
    }

    // logger writes spike results to the unified log.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "spike")
    // tap is the active event tap while one runs.
    private var tap: CFMachPort?
    // source feeds the tap into the main run loop.
    private var source: CFRunLoopSource?
    // armed is how many green button clicks the tap still swallows.
    private var armed = 0
    // swallowingUp reports whether the next mouse up belongs to a swallowed click.
    private var swallowingUp = false
    // dragLogged reports whether the current press already logged its drag.
    private var dragLogged = false

    // run performs the named command with its link parameters.
    func run(_ name: String, query: [String: String]) {
        guard let command = Command(rawValue: name) else {
            log("unknown command: \(name)")
            return
        }
        switch command {
        case .status: status()
        case .prompt: prompt()
        case .list: list()
        case .move: move(query)
        case .tap: startTap()
        case .untap: stopTap()
        case .quit: NSApp.terminate(nil)
        }
    }

    // log writes one line to the unified log and to stderr.
    private func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    // status logs the trust state, the build, and whether the sandbox is on.
    private func status() {
        let info = Bundle.main.infoDictionary ?? [:]
        let build = info["CFBundleVersion"] as? String ?? "?"
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        log("status: trusted=\(AXIsProcessTrusted()) build=\(build) sandboxed=\(sandboxed) path=\(Bundle.main.bundlePath)")
        for (index, screen) in NSScreen.screens.enumerated() {
            log("screen \(index): \(screen.localizedName) frame=\(screen.frame)")
        }
    }

    // prompt asks macOS to show the Accessibility request for this app.
    private func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        log("prompt: trusted=\(AXIsProcessTrustedWithOptions(options))")
    }

    // list logs every window of every regular app with its frame and subrole.
    private func list() {
        var count = 0
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(running.processIdentifier)
            let name = running.localizedName ?? "pid \(running.processIdentifier)"
            for window in Self.windows(appElement) {
                count += 1
                let title = Self.string(window, kAXTitleAttribute) ?? ""
                let subrole = Self.string(window, kAXSubroleAttribute) ?? "?"
                log("window: \(name) \"\(title)\" subrole=\(subrole) frame=\(Self.frame(window).map { "\($0)" } ?? "?")")
            }
        }
        log("list: \(count) windows, trusted=\(AXIsProcessTrusted())")
    }

    // move sets the frame of the first window of an app, TextEdit unless app= names another.
    private func move(_ query: [String: String]) {
        let target = query["app"] ?? "TextEdit"
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == target }),
              let window = Self.windows(AXUIElementCreateApplication(running.processIdentifier)).first
        else {
            log("move: no window for \(target)")
            return
        }
        let want = CGRect(
            x: Double(query["x"] ?? "") ?? 200,
            y: Double(query["y"] ?? "") ?? 200,
            width: Double(query["w"] ?? "") ?? 800,
            height: Double(query["h"] ?? "") ?? 600
        )
        let before = Self.frame(window)
        var size = want.size
        var origin = want.origin
        let sizeValue = AXValueCreate(.cgSize, &size)!
        let originValue = AXValueCreate(.cgPoint, &origin)!
        let first = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let second = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        let third = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let after = Self.frame(window)
        log("move: \(target) before=\(before.map { "\($0)" } ?? "?") want=\(want) after=\(after.map { "\($0)" } ?? "?") errors=\(first.rawValue),\(second.rawValue),\(third.rawValue)")
    }

    // startTap installs an active session event tap that logs drags and swallows one green button
    // click.
    private func startTap() {
        guard tap == nil else {
            log("tap: already running")
            return
        }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
        let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let spike = Unmanaged<Spike>.fromOpaque(refcon).takeUnretainedValue()
                let point = event.location
                let swallow = MainActor.assumeIsolated { spike.handle(type, at: point) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let created else {
            log("tap: create failed, trusted=\(AXIsProcessTrusted())")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        source = runLoopSource
        armed = 1
        log("tap: running, armed to swallow \(armed) green button click")
    }

    // stopTap removes the event tap.
    private func stopTap() {
        guard let tap, let source else {
            log("untap: no tap")
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = nil
        self.source = nil
        log("untap: stopped")
    }

    // handle reacts to one tapped event and reports whether to swallow it.
    private func handle(_ type: CGEventType, at point: CGPoint) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            log("tap: disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input"), enabling again")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            dragLogged = false
            let subrole = Self.subrole(at: point)
            guard armed > 0, subrole == kAXZoomButtonSubrole else { return false }
            armed -= 1
            swallowingUp = true
            log("tap: swallowed green button down at \(point)")
            return true
        case .leftMouseDragged:
            if !dragLogged {
                dragLogged = true
                log("tap: drag seen at \(point)")
            }
            return false
        case .leftMouseUp:
            guard swallowingUp else { return false }
            swallowingUp = false
            log("tap: swallowed green button up at \(point)")
            return true
        default:
            return false
        }
    }

    // windows returns the windows of an app element.
    private static func windows(_ appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    // string returns a string attribute of an element.
    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // frame returns a window's position and size in global top-left coordinates.
    private static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    // subrole returns the subrole of the element under a global point.
    private static func subrole(at point: CGPoint) -> String? {
        var element: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element
        else { return nil }
        return string(element, kAXSubroleAttribute)
    }
}
