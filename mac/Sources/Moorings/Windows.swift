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
    // apps caches the app element for each process.
    private var apps: [pid_t: AXUIElement] = [:]
    // scanned holds the processes the last scan read windows from.
    private(set) var scanned: Set<pid_t> = []

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
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for running in NSWorkspace.shared.runningApplications where pids.contains(running.processIdentifier) {
            guard let bundle = running.bundleIdentifier, !running.isHidden,
                  running.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { continue }
            let app = appElement(running.processIdentifier)
            scanned.insert(running.processIdentifier)
            for el in Self.array(app, kAXWindowsAttribute) {
                guard let id = Self.id(el), rank[id] != nil, let info = info(el, id: id, bundle: bundle, screens: screens)
                else { continue }
                seen[id] = el
                found.append(info)
            }
            if running.processIdentifier == front, let el = Self.element(app, kAXFocusedWindowAttribute) {
                focusedID = Self.id(el)
            }
        }
        elements = seen
        panels = panels.filter { seen[$0.key] != nil }
        found.sort { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        if let focusedID, let i = found.firstIndex(where: { $0.id == focusedID }) {
            found.insert(found.remove(at: i), at: 0)
        }
        return (found, found.first { $0.id == focusedID })
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

    // frame reads where the window with id is now, nil when it cannot be read.
    func frame(_ id: WindowID) -> Frame? {
        elements[id].flatMap { Self.frame($0) }
    }

    // raise brings the window with id to the front and activates its app.
    func raise(_ id: WindowID) {
        guard let el = elements[id] else { return }
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        var pid: pid_t = 0
        if AXUIElementGetPid(el, &pid) == .success {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
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
    // window, it is minimized, or its frame cannot be read.
    private func info(_ el: AXUIElement, id: WindowID, bundle: String, screens: Screens) -> WindowInfo? {
        guard Self.string(el, kAXRoleAttribute) == kAXWindowRole, Self.document(el),
              !Self.bool(el, kAXMinimizedAttribute), let frame = Self.frame(el)
        else { return nil }
        let panel = panels[id] ?? Self.filePanel(el)
        panels[id] = panel
        return WindowInfo(
            id: id,
            bundle: bundle,
            frame: frame,
            onUltrawide: screens.ultrawide != nil && screens.index(frame) == screens.ultrawide,
            isMain: Self.bool(el, kAXMainAttribute),
            isFilePanel: panel,
            isFullScreen: Self.bool(el, "AXFullScreen")
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
