import AppKit
import ApplicationServices

import MooringsCore

// axWindowID reads the CGWindowID behind a window element. It is private to the system but has
// been stable since macOS 10.6, and every window manager relies on it.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// Screens holds the attached displays in global top-left coordinates.
struct Screens {
    // full lists each screen's full frame.
    let full: [Frame]
    // usable lists each screen's frame without the menu bar and the Dock.
    let usable: [Frame]
    // ultrawide is the index of the ultrawide, nil when none is attached.
    let ultrawide: Int?

    // current reads the attached screens.
    static func current() -> Screens {
        let screens = NSScreen.screens
        let primary = screens.first?.frame.height ?? 0
        let flip = { (r: NSRect) in Frame(x: r.minX, y: primary - r.maxY, w: r.width, h: r.height) }
        let full = screens.map { flip($0.frame) }
        return Screens(full: full, usable: screens.map { flip($0.visibleFrame) }, ultrawide: Layout.ultrawide(full))
    }

    // wide returns the ultrawide's usable frame, nil when none is attached.
    var wide: Frame? { ultrawide.map { usable[$0] } }

    // index returns the screen f overlaps most, nil when it overlaps none.
    func index(_ f: Frame) -> Int? {
        var best: Int?
        var bestArea = 0.0
        for (i, s) in full.enumerated() {
            let w = min(f.x + f.w, s.x + s.w) - max(f.x, s.x)
            let h = min(f.y + f.h, s.y + s.h) - max(f.y, s.y)
            if w > 0, h > 0, w * h > bestArea {
                best = i
                bestArea = w * h
            }
        }
        return best
    }
}

// Windows reads and moves other apps' windows through Accessibility.
@MainActor
final class Windows {
    // timeout caps how long one Accessibility call to a busy app may block the main thread.
    static let timeout: Float = 0.25

    // elements maps each window seen in the last scan to its element.
    private(set) var elements: [WindowID: AXUIElement] = [:]
    // panels caches whether a window is an open or save panel, read once per window.
    private var panels: [WindowID: Bool] = [:]
    // zooms caches each window's green button rect with the frame it was read at, so it is asked
    // for again only when the window moves.
    private var zooms: [WindowID: (frame: Frame, rect: Frame?)] = [:]
    // apps caches the app element for each process.
    private var apps: [pid_t: AXUIElement] = [:]
    // scanned holds the processes the last scan read windows from.
    private(set) var scanned: Set<pid_t> = []

    // lastFront is the last app other than moorings to come to the front.
    var lastFront: pid_t?

    // front returns the front app, or the one before moorings when a link brought moorings forward.
    private var front: pid_t? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == ProcessInfo.processInfo.processIdentifier ? lastFront : pid
    }

    // trusted reports whether moorings has Accessibility access.
    var trusted: Bool { AXIsProcessTrusted() }

    // scan returns the movable windows on screen, front-most first, and the focused one.
    func scan(_ screens: Screens) -> (windows: [WindowInfo], focused: WindowInfo?) {
        let order = Self.onScreen()
        let rank = Dictionary(order.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let pids = Set(order.map(\.pid))
        var found: [WindowInfo] = []
        var seen: [WindowID: AXUIElement] = [:]
        var focusedID: WindowID?
        scanned = []
        let front = front
        for running in NSWorkspace.shared.runningApplications where pids.contains(running.processIdentifier) {
            guard let bundle = running.bundleIdentifier, !running.isHidden,
                  running.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { continue }
            let app = appElement(running.processIdentifier)
            scanned.insert(running.processIdentifier)
            let main = Self.element(app, kAXMainWindowAttribute).flatMap { Self.id($0) }
            for el in Self.array(app, kAXWindowsAttribute) {
                guard let id = Self.id(el), rank[id] != nil,
                      let info = info(el, id: id, bundle: bundle, isMain: id == main, screens: screens)
                else { continue }
                seen[id] = el
                found.append(info)
            }
            if running.processIdentifier == front, let el = Self.element(app, kAXFocusedWindowAttribute) {
                focusedID = Self.id(el)
            }
        }
        found = WindowInfo.promotingLone(found)
        elements = seen
        panels = panels.filter { seen[$0.key] != nil }
        zooms = zooms.filter { seen[$0.key] != nil }
        found.sort { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        if let focusedID, let i = found.firstIndex(where: { $0.id == focusedID }) {
            found.insert(found.remove(at: i), at: 0)
        }
        return (found, found.first { $0.id == focusedID })
    }

    // explain returns one line per app with on-screen windows saying what the scan reads from it,
    // and why each of its windows is kept or dropped.
    func explain(_ screens: Screens) -> [String] {
        let order = Self.onScreen()
        let rank = Set(order.map(\.id))
        let pids = Set(order.map(\.pid))
        var out: [String] = []
        for running in NSWorkspace.shared.runningApplications where pids.contains(running.processIdentifier) {
            let bundle = running.bundleIdentifier ?? "?"
            let app = appElement(running.processIdentifier)
            let start = Date()
            var raw: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let els = raw as? [AXUIElement] ?? []
            let cg = order.filter { $0.pid == running.processIdentifier }.map(\.id)
            out.append("app \(bundle) pid=\(running.processIdentifier) hidden=\(running.isHidden) ax=\(err.rawValue) \(ms)ms axWindows=\(els.count) cgWindows=\(cg)")
            for el in els {
                guard let id = Self.id(el) else {
                    out.append("  drop: no window id")
                    continue
                }
                let why: String
                if !rank.contains(id) {
                    why = "drop: not on screen"
                } else if Self.string(el, kAXRoleAttribute) != kAXWindowRole {
                    why = "drop: role \(Self.string(el, kAXRoleAttribute) ?? "nil")"
                } else if !Self.document(el) {
                    why = "drop: subrole \(Self.string(el, kAXSubroleAttribute) ?? "nil")"
                } else if Self.bool(el, kAXMinimizedAttribute) {
                    why = "drop: minimized"
                } else if Self.frame(el) == nil {
                    why = "drop: no frame"
                } else {
                    why = "keep"
                }
                out.append("  window \(id) \(why)")
            }
        }
        return out
    }

    // move puts the window with id at frame. Size goes first and again last, so a window crossing
    // displays lands at the size asked for.
    func move(_ id: WindowID, to frame: Frame) {
        guard let el = elements[id] else { return }
        var size = CGSize(width: frame.w, height: frame.h)
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return
        }
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeValue)
    }

    // position moves the window with id so its top-left corner is at x and y, leaving its size alone.
    func position(_ id: WindowID, x: Double, y: Double) {
        var origin = CGPoint(x: x, y: y)
        guard let el = elements[id], let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, value)
    }

    // resize sets the size of the window with id and leaves its position to whatever is moving it.
    func resize(_ id: WindowID, w: Double, h: Double) {
        var size = CGSize(width: w, height: h)
        guard let el = elements[id], let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, value)
    }

    // enhancedUIKey is the app attribute VoiceOver and some apps set, which makes an app animate its
    // own resizing and land off the frame asked for.
    static let enhancedUIKey = "AXEnhancedUserInterface" as CFString

    // slide moves the window with id from start to frame through Behavior.steps over
    // Behavior.animationTime, then lands it exactly with move(_:to:enhancedUI:).
    func slide(_ id: WindowID, from start: Frame, to frame: Frame, enhancedUI mode: EnhancedUIMode) {
        let steps = Behavior.steps(from: start, to: frame)
        let pause = Behavior.animationTime / Double(steps.count - 1)
        for f in steps.dropFirst().dropLast() {
            move(id, to: f)
            Thread.sleep(forTimeInterval: pause)
        }
        move(id, to: frame, enhancedUI: mode)
    }

    // move puts the window with id at frame with its app's Enhanced UI off for the move, and turns it
    // back on afterward when mode says to.
    func move(_ id: WindowID, to frame: Frame, enhancedUI mode: EnhancedUIMode) {
        var pid: pid_t = 0
        guard let el = elements[id], AXUIElementGetPid(el, &pid) == .success else {
            move(id, to: frame)
            return
        }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let on = AXUIElementCopyAttributeValue(app, Self.enhancedUIKey, &value) == .success
            && (value as? Bool) == true
        if on {
            AXUIElementSetAttributeValue(app, Self.enhancedUIKey, kCFBooleanFalse)
        }
        move(id, to: frame)
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if on, Behavior.restoresEnhancedUI(mode, bundle: bundle, assistive: NSWorkspace.shared.isVoiceOverEnabled) {
            AXUIElementSetAttributeValue(app, Self.enhancedUIKey, kCFBooleanTrue)
        }
    }

    // dropEnhancedUI turns off the Enhanced UI of the app with pid.
    static func dropEnhancedUI(_ pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), enhancedUIKey, kCFBooleanFalse)
    }

    // frame reads where the window with id is now, nil when it cannot be read.
    func frame(_ id: WindowID) -> Frame? {
        elements[id].flatMap { Self.frame($0) }
    }

    // close presses the close button of the window with id.
    func close(_ id: WindowID) {
        guard let el = elements[id], let button = Self.element(el, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    // cancel presses the Cancel button of the open or save panel with id and reports whether it
    // found one. Keys posted to the app miss the panel, which is served out of process.
    func cancel(_ id: WindowID) -> Bool {
        guard let el = elements[id], let button = Self.descendant(el, depth: 8, where: {
            Self.string($0, kAXIdentifierAttribute) == "CancelButton"
        }) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    // descendant returns the first element under el, breadth first and at most depth levels down,
    // that match accepts.
    private static func descendant(_ el: AXUIElement, depth: Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var level = array(el, kAXChildrenAttribute)
        for _ in 0..<depth where !level.isEmpty {
            if let found = level.first(where: match) {
                return found
            }
            level = level.flatMap { array($0, kAXChildrenAttribute) }
        }
        return nil
    }

    // minimize sends the window with id to the Dock.
    func minimize(_ id: WindowID) {
        guard let el = elements[id] else { return }
        AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    // title returns the title of the window with id, empty when it has none.
    func title(_ id: WindowID) -> String {
        elements[id].flatMap { Self.string($0, kAXTitleAttribute) } ?? ""
    }

    // exitFullScreen asks the window with id to leave native fullscreen.
    func exitFullScreen(_ id: WindowID) {
        guard let el = elements[id] else { return }
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    // front returns the on-screen windows at the normal layer with their frames, front-most first.
    static func front() -> [(id: WindowID, frame: Frame)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let id = entry[kCGWindowNumber as String] as? WindowID,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"]
            else { return nil }
            return (id, Frame(x: x, y: y, w: w, h: h))
        }
    }

    // hit reads the element at p and the window it belongs to: the window's id, frame and green button
    // and the element's role. It returns nil when no window is there.
    static func hit(_ p: CGPoint) -> (id: WindowID, frame: Frame, button: Frame?, role: String?)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &found) == .success, let el = found
        else { return nil }
        let role = string(el, kAXRoleAttribute)
        guard let win = role == kAXWindowRole ? el : element(el, kAXWindowAttribute), let id = id(win),
              let frame = frame(win)
        else { return nil }
        return (id, frame, element(win, kAXZoomButtonAttribute).flatMap { Self.frame($0) }, role)
    }

    // button reads the element at p and returns its window's id and the element's subrole, which names
    // a title bar button. It returns nil when no window is there.
    static func button(_ p: CGPoint) -> (id: WindowID, subrole: String?)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &found) == .success, let el = found,
              let win = element(el, kAXWindowAttribute), let id = id(win)
        else { return nil }
        return (id, string(el, kAXSubroleAttribute))
    }

    // raiseSettle is how long in seconds raise waits after activating an app before it raises the
    // window again, because activation can bring the app's previous main window back in front.
    static let raiseSettle = 0.15

    // raise brings the window with id to the front and activates its app. It makes the window its
    // app's main window and raises it, activates the app, then does both again once activation has
    // settled, since activating an app brings its main window forward.
    func raise(_ id: WindowID) {
        guard let el = elements[id] else { return }
        Self.makeFront(el)
        var pid: pid_t = 0
        guard AXUIElementGetPid(el, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.raiseSettle) {
            Self.makeFront(el)
        }
    }

    // makeFront makes el its app's main window and raises it.
    private static func makeFront(_ el: AXUIElement) {
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    // alive returns the ids of every window that exists, on any Space.
    static func alive() -> Set<WindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return Set((list ?? []).compactMap { $0[kCGWindowNumber as String] as? WindowID })
    }

    // forget drops the cached element of a process that quit.
    func forget(_ pid: pid_t) {
        apps[pid] = nil
    }

    // appElement returns the cached element for pid, with a short messaging timeout.
    private func appElement(_ pid: pid_t) -> AXUIElement {
        if let el = apps[pid] {
            return el
        }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, Self.timeout)
        apps[pid] = el
        return el
    }

    // info describes window el, or returns nil when moorings may not move it: it is not a document
    // window, it is minimized, or its frame cannot be read. isMain is whether the app names el its
    // main window, which an app reports even while it is not active.
    private func info(_ el: AXUIElement, id: WindowID, bundle: String, isMain: Bool, screens: Screens) -> WindowInfo? {
        guard Self.string(el, kAXRoleAttribute) == kAXWindowRole, Self.document(el),
              !Self.bool(el, kAXMinimizedAttribute), let frame = Self.frame(el)
        else { return nil }
        let panel = panels[id] ?? Self.filePanel(el)
        panels[id] = panel
        var zoom = zooms[id]
        if zoom == nil || zoom!.frame != frame {
            zoom = (frame, Self.element(el, kAXZoomButtonAttribute).flatMap { Self.frame($0) })
            zooms[id] = zoom
        }
        return WindowInfo(
            id: id,
            bundle: bundle,
            frame: frame,
            onUltrawide: screens.ultrawide != nil && screens.index(frame) == screens.ultrawide,
            isMain: isMain,
            isFilePanel: panel,
            isFullScreen: Self.bool(el, "AXFullScreen"),
            zoomRect: zoom?.rect
        )
    }

    // document reports whether el is a document window: a standard window, or a dialog with a zoom
    // button, which is how TextEdit's documents report themselves.
    private static func document(_ el: AXUIElement) -> Bool {
        switch string(el, kAXSubroleAttribute) {
        case kAXStandardWindowSubrole: true
        case kAXDialogSubrole: element(el, kAXZoomButtonAttribute) != nil
        default: false
        }
    }

    // filePanel reports whether el is an open or save panel, which AppKit names by AXIdentifier.
    private static func filePanel(_ el: AXUIElement) -> Bool {
        let ident = string(el, kAXIdentifierAttribute)
        return ident == "open-panel" || ident == "save-panel"
    }

    // onScreen returns the on-screen windows at the normal layer, front-most first, with their
    // owners.
    private static func onScreen() -> [(id: WindowID, pid: pid_t)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let id = entry[kCGWindowNumber as String] as? WindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            else { return nil }
            return (id, pid)
        }
    }

    // id returns the window id of el.
    private static func id(_ el: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        return axWindowID(el, &id) == .success && id != 0 ? id : nil
    }

    // value returns an attribute of el.
    private static func value(_ el: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success ? value : nil
    }

    // string returns a string attribute of el.
    private static func string(_ el: AXUIElement, _ attribute: String) -> String? {
        value(el, attribute) as? String
    }

    // bool returns a boolean attribute of el, false when it cannot be read.
    private static func bool(_ el: AXUIElement, _ attribute: String) -> Bool {
        value(el, attribute) as? Bool ?? false
    }

    // element returns an element attribute of el.
    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(el, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(v, to: AXUIElement.self)
    }

    // array returns an element list attribute of el.
    private static func array(_ el: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(el, attribute) as? [AXUIElement] ?? []
    }

    // frame returns el's position and size in global top-left coordinates.
    private static func frame(_ el: AXUIElement) -> Frame? {
        guard let p = value(el, kAXPositionAttribute), let s = value(el, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(p, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(s, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return Frame(x: origin.x, y: origin.y, w: size.width, h: size.height)
    }
}
