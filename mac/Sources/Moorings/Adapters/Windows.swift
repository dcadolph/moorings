import AppKit
import ApplicationServices

import MooringsCore
import MooringsEngine

// axWindowID reads the CGWindowID behind a window element. It is private to the system but has
// been stable since macOS 10.6, and every window manager relies on it.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension Screens {
    // current reads the attached screens.
    static func current() -> Screens {
        let screens = NSScreen.screens
        let primary = screens.first?.frame.height ?? 0
        let flip = { (r: NSRect) in Frame(x: r.minX, y: primary - r.maxY, w: r.width, h: r.height) }
        let full = screens.map { flip($0.frame) }
        return Screens(full: full, usable: screens.map { flip($0.visibleFrame) }, ultrawide: Layout.ultrawide(full))
    }
}

// Windows reads and moves other apps' windows through Accessibility.
@MainActor
final class Windows {
    // timeout caps how long one Accessibility call to a busy app may block the main thread.
    static let timeout: Float = 0.25

    // elements maps each window a scan or read has seen to its element, kept until the window is gone
    // or its app quits, so a minimized window or one on another Space can still be acted on.
    private(set) var elements: [WindowID: AXUIElement] = [:]
    // kept lists the windows the last scan kept, plus any read alone since.
    private var kept: Set<WindowID> = []
    // zooms caches each window's green button rect with the frame it was read at, so it is asked
    // for again only when the window moves.
    private var zooms: [WindowID: (frame: Frame, rect: Frame?)] = [:]
    // apps caches the app element for each process.
    private var apps: [pid_t: AXUIElement] = [:]
    // RunningApp is what a scan needs from one running app, cached so a pass asks the app nothing.
    private struct RunningApp {
        // app is the running app.
        let app: NSRunningApplication
        // bundle is the app's bundle id, which does not change while it runs.
        let bundle: String?
        // hidden is whether the app was hidden when a full pass last asked.
        var hidden: Bool
    }

    // running caches the running app for each process with an on-screen window, so a scan never walks
    // every running app and asks each for its process identifier.
    private var running: [pid_t: RunningApp] = [:]
    // scanned holds the processes the last scan read windows from.
    private(set) var scanned: Set<pid_t> = []
    // last holds each process's windows from the last scan, carried through a pass the app is too
    // busy to answer or that does not read it.
    private var last: [pid_t: [WindowInfo]] = [:]
    // listed holds each process's on-screen window frames from the window server at the last scan.
    private var listed: [pid_t: [WindowID: Frame]] = [:]
    // slow holds the processes whose last window read could not complete.
    private var slow: Set<pid_t> = []
    // lastPlan is which apps the last scan read.
    private(set) var lastPlan: PassPlan = .full
    // focus is the front app and its focused window at the last scan that read the front app, so a
    // scan that carries the front app keeps its focus.
    private var focus: (pid: pid_t, id: WindowID?)?

    // lastFront is the last app other than moorings to come to the front, as the activation
    // notifications tell it.
    var lastFront: pid_t?
    // refusedIDs holds the windows whose position or size Accessibility reported it cannot set.
    private(set) var refusedIDs: Set<WindowID> = []
    // appWoke holds when each app last sent a window event or had a window moved by an action.
    var appWoke: [pid_t: Double] = [:]
    // echoes holds the frame a placement asked for each window, with when it did, so the window's
    // own move events and the pass after read nothing the placement already read. move sets it for
    // a move from a known frame, which only placements make.
    var echoes: [WindowID: (frame: Frame, at: Double)] = [:]
    // lastFull is when the last scan that read every app ran.
    private(set) var lastFull = -Double.infinity
    // Listing is one window on the window server list: its id, its owner and its frame.
    typealias Listing = (id: WindowID, pid: pid_t, frame: Frame)
    // list asks the window server for its list, front-most first.
    private let list: @MainActor () -> [Listing]
    // lookup asks the window server for one window as list would show it, nil when list would not.
    private let lookup: @MainActor (WindowID) -> Listing?
    // listing is the list the last scan used, which a pass woken by an action's own move carries.
    private var listing: [Listing] = []
    // lastScan is when the last scan ran, by system uptime.
    private var lastScan = -Double.infinity
    // readBack holds where each window placed since the last scan read back, so a carried list puts
    // it there.
    private var readBack: [WindowID: Frame] = [:]

    // init asks the window server for its list with list and for one window with lookup.
    init(
        list: @escaping @MainActor () -> [Listing] = Windows.onScreen,
        lookup: @escaping @MainActor (WindowID) -> Listing? = Windows.onScreen
    ) {
        self.list = list
        self.lookup = lookup
    }

    // front returns the front app, or the one before moorings when a link brought moorings forward.
    private var front: pid_t? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return pid == ProcessInfo.processInfo.processIdentifier ? lastFront : pid
    }

    // trusted reports whether moorings has Accessibility access.
    var trusted: Bool { AXIsProcessTrusted() }

    // scan returns the movable windows on screen, front-most first, and the focused one. decide
    // picks the apps read through Accessibility from the window server's frames by process now, at
    // the last scan, the slow processes and the front app. Any app not read before is always read,
    // and every other app is carried from the last scan at its window server frames. The front app
    // is carried with its focus only when the last scan that read it saw it in front. carry uses the
    // last window server list, with the windows placed since at their new frames, instead of a new one.
    // tracked takes the front app from the activation notifications instead of asking LaunchServices.
    func scan(
        _ screens: Screens, carry: Bool = false, tracked: Bool = false,
        decide: (
            _ listed: [pid_t: [WindowID: Frame]], _ previous: [pid_t: [WindowID: Frame]], _ slow: Set<pid_t>,
            _ front: pid_t?
        ) -> PassPlan = { _, _, _, _ in .full }
    ) -> (windows: [WindowInfo], focused: WindowInfo?) {
        let order = carry ? carried() : list()
        let rank = Dictionary(order.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let pids = Set(order.map(\.pid))
        var found: [WindowInfo] = []
        var seen: [WindowID: AXUIElement] = [:]
        var focusedID: WindowID?
        var byPid: [pid_t: [WindowInfo]] = [:]
        scanned = []
        let front = tracked ? (lastFront ?? front) : front
        let frames = Dictionary(order.map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        var now: [pid_t: [WindowID: Frame]] = [:]
        for w in order {
            now[w.pid, default: [:]][w.id] = w.frame
        }
        let plan = decide(now, listed, slow, front)
        listed = now
        listing = order
        lastScan = ProcessInfo.processInfo.systemUptime
        readBack = [:]
        lastPlan = plan
        running = running.filter { pids.contains($0.key) }
        let me = ProcessInfo.processInfo.processIdentifier
        for pid in pids where pid != me {
            if running[pid] == nil, let app = NSRunningApplication(processIdentifier: pid) {
                running[pid] = RunningApp(app: app, bundle: app.bundleIdentifier, hidden: app.isHidden)
            } else if plan == .full, let app = running[pid]?.app {
                running[pid]?.hidden = app.isHidden
            }
            guard let cached = running[pid], let bundle = cached.bundle, !cached.hidden else { continue }
            if case let .apps(reads) = plan, !reads.contains(pid), let kept = last[pid],
                pid != front || focus?.pid == pid
            {
                if pid == front {
                    focusedID = focus?.id
                }
                let carried = WindowInfo.carrying(kept, frames: frames)
                for w in carried {
                    seen[w.id] = elements[w.id]
                }
                byPid[pid] = carried
                found += carried
                continue
            }
            let app = appElement(pid)
            scanned.insert(pid)
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .cannotComplete {
                slow.insert(pid)
                let carried = WindowInfo.carrying(last[pid] ?? [], frames: frames)
                for w in carried {
                    seen[w.id] = elements[w.id]
                }
                byPid[pid] = carried
                found += carried
                continue
            }
            slow.remove(pid)
            let main = Self.element(app, kAXMainWindowAttribute).flatMap { Self.id($0) }
            for el in raw as? [AXUIElement] ?? [] {
                guard let id = Self.id(el), rank[id] != nil,
                    let info = info(el, id: id, bundle: bundle, isMain: id == main, screens: screens)
                else { continue }
                seen[id] = el
                found.append(info)
                byPid[pid, default: []].append(info)
            }
            if pid == front {
                focusedID = Self.element(app, kAXFocusedWindowAttribute).flatMap { Self.id($0) }
                focus = (pid, focusedID)
            }
        }
        found = WindowInfo.promotingLone(found)
        last = byPid
        elements.merge(seen) { _, new in new }
        kept = Set(seen.keys)
        zooms = zooms.filter { seen[$0.key] != nil }
        found.sort { rank[$0.id, default: .max] < rank[$1.id, default: .max] }
        if let focusedID, let i = found.firstIndex(where: { $0.id == focusedID }) {
            found.insert(found.remove(at: i), at: 0)
        }
        return (found, found.first { $0.id == focusedID })
    }

    // focused reads the front app's focused window alone, without a scan, and caches its element so
    // it can be moved. It returns nil when the window is not one a scan would keep or anything
    // cannot be read, and the caller then scans.
    func focused(_ screens: Screens) -> WindowInfo? {
        guard let pid = front, pid != ProcessInfo.processInfo.processIdentifier,
            let el = Self.element(appElement(pid), kAXFocusedWindowAttribute), let id = Self.id(el)
        else { return nil }
        return read(el, id: id, pid: pid, screens: screens)
    }

    // window reads the window with id alone, without a scan, when the store holds its element, and
    // returns nil otherwise or when it cannot be read.
    func window(_ id: WindowID, screens: Screens) -> WindowInfo? {
        guard let el = elements[id], let pid = Self.pid(el) else { return nil }
        return read(el, id: id, pid: pid, screens: screens)
    }

    // read describes window el with id of the app with pid as a scan would, and caches its element.
    // It returns nil when the app is hidden or has no bundle id, or when a scan would drop the window.
    private func read(_ el: AXUIElement, id: WindowID, pid: pid_t, screens: Screens) -> WindowInfo? {
        guard lookup(id)?.pid == pid else { return nil }
        if running[pid] == nil, let app = NSRunningApplication(processIdentifier: pid) {
            running[pid] = RunningApp(app: app, bundle: app.bundleIdentifier, hidden: app.isHidden)
        }
        guard let cached = running[pid], let bundle = cached.bundle, !cached.hidden else { return nil }
        let main = Self.element(appElement(pid), kAXMainWindowAttribute).flatMap { Self.id($0) }
        guard let info = info(el, id: id, bundle: bundle, isMain: id == main, screens: screens) else { return nil }
        elements[id] = el
        kept.insert(id)
        return info
    }

    // explain returns one line per app with on-screen windows saying what the scan reads from it,
    // and why each of its windows is kept or dropped.
    func explain(_ screens: Screens) -> [String] {
        let order = list()
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
            out.append(
                "app \(bundle) pid=\(running.processIdentifier) hidden=\(running.isHidden) ax=\(err.rawValue) \(ms)ms axWindows=\(els.count) cgWindows=\(cg)"
            )
            for el in els {
                guard let id = Self.id(el) else {
                    out.append("  drop: no window id")
                    continue
                }
                let why: String
                let traits = rank.contains(id) ? Self.traits(el).traits : WindowTraits()
                if !rank.contains(id) {
                    why = "drop: not on screen"
                } else if traits.role != kAXWindowRole {
                    why = "drop: role \(traits.role ?? "nil")"
                } else if !traits.document {
                    why = "drop: subrole \(traits.subrole ?? "nil")"
                } else if traits.minimized {
                    why = "drop: minimized"
                } else if traits.frame == nil {
                    why = "drop: no frame"
                } else {
                    why = "keep"
                }
                out.append("  window \(id) \(why)")
            }
        }
        return out
    }

    // move puts the window with id at frame with the writes MoveSteps picks from current, the frame
    // the window has now when the caller just read it. Without it, size goes first and again last, so
    // a window crossing displays lands at the size asked for.
    func move(_ id: WindowID, to frame: Frame, from current: Frame? = nil) {
        guard let el = elements[id] else { return }
        var size = CGSize(width: frame.w, height: frame.h)
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return
        }
        for step in MoveSteps.steps(from: current, to: frame) {
            let err =
                switch step {
                case .size: AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeValue)
                case .position: AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, originValue)
                }
            if err == .attributeUnsupported {
                refusedIDs.insert(id)
            }
        }
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
    // back on afterward when mode says to. current is the frame the window has now, when known.
    func move(_ id: WindowID, to frame: Frame, enhancedUI mode: EnhancedUIMode, from current: Frame? = nil) {
        var pid: pid_t = 0
        guard let el = elements[id], AXUIElementGetPid(el, &pid) == .success else {
            move(id, to: frame, from: current)
            return
        }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let on =
            AXUIElementCopyAttributeValue(app, Self.enhancedUIKey, &value) == .success
            && (value as? Bool) == true
        if on {
            AXUIElementSetAttributeValue(app, Self.enhancedUIKey, kCFBooleanFalse)
        }
        move(id, to: frame, from: current)
        guard on else { return }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        if Behavior.restoresEnhancedUI(mode, bundle: bundle, assistive: NSWorkspace.shared.isVoiceOverEnabled) {
            AXUIElementSetAttributeValue(app, Self.enhancedUIKey, kCFBooleanTrue)
        }
    }

    // dropEnhancedUI turns off the Enhanced UI of the app with pid.
    static func dropEnhancedUI(_ pid: pid_t) {
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), enhancedUIKey, kCFBooleanFalse)
    }

    // frame reads where the window with id is now, nil when it cannot be read. A window placed since
    // the last scan keeps the frame read, for a carried list.
    func frame(_ id: WindowID) -> Frame? {
        guard let f = elements[id].flatMap({ Self.frame($0) }) else { return nil }
        if let e = echoes[id], e.at > lastScan {
            readBack[id] = f
        }
        return f
    }

    // carried returns the last window server list with each window placed since the last scan where
    // it read back, or where it was asked to go when it was not read.
    private func carried() -> [Listing] {
        listing.map { w in
            guard let e = echoes[w.id], e.at > lastScan else { return w }
            return (w.id, w.pid, readBack[w.id] ?? e.frame)
        }
    }

    // close presses the close button of the window with id.
    func close(_ id: WindowID) {
        guard let el = elements[id], let button = Self.element(el, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    // cancel presses the Cancel button of the open or save panel with id and reports whether it
    // found one. Keys posted to the app miss the panel, which is served out of process.
    func cancel(_ id: WindowID) -> Bool {
        guard let el = elements[id],
            let button = Self.descendant(
                el, depth: 8,
                where: {
                    Self.string($0, kAXIdentifierAttribute) == "CancelButton"
                })
        else { return false }
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

    // title returns the title of the window with id, nil when the window is gone or its title is empty.
    func title(_ id: WindowID) -> String? {
        elements[id].flatMap { Self.string($0, kAXTitleAttribute) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    // hit returns the window under p, in top-left coordinates, nil when no window is there.
    func hit(_ p: Point) -> WindowID? {
        Self.hit(CGPoint(x: p.x, y: p.y))?.id
    }

    // exitFullScreen asks the window with id to leave native fullscreen.
    func exitFullScreen(_ id: WindowID) {
        guard let el = elements[id] else { return }
        AXUIElementSetAttributeValue(el, "AXFullScreen" as CFString, kCFBooleanFalse)
    }

    // front returns the on-screen windows at the normal layer with their frames, front-most first.
    static func front() -> [(id: WindowID, frame: Frame)] {
        let list =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
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
            let app = NSRunningApplication(processIdentifier: pid)
        else { return }
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

    // listed returns the id of every window in the window server's list, on any Space, with whether
    // it is on screen.
    static func listed() -> [WindowID: Bool] {
        let list =
            CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        var out: [WindowID: Bool] = [:]
        for entry in list ?? [] {
            guard let id = entry[kCGWindowNumber as String] as? WindowID else { continue }
            out[id] = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
        }
        return out
    }

    // living returns the ids in listed less the off-screen ones destroyed reports. An app such as
    // TextEdit keeps a closed window in the window server's list until it quits, so the list alone
    // cannot tell a closed window from one minimized or on another Space.
    nonisolated static func living(_ listed: [WindowID: Bool], destroyed: (WindowID) -> Bool) -> Set<WindowID> {
        Set(listed.compactMap { id, onscreen in onscreen || !destroyed(id) ? id : nil })
    }

    // destroyed reports whether el belongs to a closed window. A closed window's element answers
    // every read as invalid, while one minimized or on another Space still answers.
    static func destroyed(_ el: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &value) == .invalidUIElement
    }

    // forget drops the cached elements, windows and frames of a process that quit.
    func forget(_ pid: pid_t) {
        elements = elements.filter { Self.pid($0.value).map { $0 != pid } ?? false }
        apps[pid] = nil
        last[pid] = nil
        listed[pid] = nil
        slow.remove(pid)
    }

    // pid returns the process that owns the window with id, nil when the store holds no element for it.
    func pid(_ id: WindowID) -> pid_t? {
        var pid: pid_t = 0
        guard let el = elements[id], AXUIElementGetPid(el, &pid) == .success else { return nil }
        return pid
    }

    // pid returns the process that owns el, nil when it cannot be read.
    static func pid(_ el: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(el, &pid) == .success ? pid : nil
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
        let (traits, zoomButton) = Self.traits(el)
        guard traits.movable, let frame = traits.frame else { return nil }
        var zoom = zooms[id]
        if zoom == nil || zoom!.frame != frame {
            zoom = (frame, zoomButton.flatMap { Self.frame($0) })
            zooms[id] = zoom
        }
        return WindowInfo(
            id: id,
            bundle: bundle,
            frame: frame,
            onUltrawide: screens.ultrawide != nil && screens.index(frame) == screens.ultrawide,
            isMain: isMain,
            isFilePanel: traits.filePanel,
            isFullScreen: traits.fullScreen,
            zoomRect: zoom?.rect
        )
    }

    // keeps reports whether the last scan kept the window with id.
    func keeps(_ id: WindowID?) -> Bool {
        id.map { kept.contains($0) } ?? false
    }

    // eligible reports whether a scan would keep el by its kind: a document window or a file panel.
    static func eligible(_ el: AXUIElement) -> Bool {
        document(el) || filePanel(el)
    }

    // document reports whether el is a document window by the rule in WindowTraits, asking for the
    // zoom button only for a dialog.
    private static func document(_ el: AXUIElement) -> Bool {
        let subrole = string(el, kAXSubroleAttribute)
        let zoom = subrole == kAXDialogSubrole && element(el, kAXZoomButtonAttribute) != nil
        return WindowTraits(subrole: subrole, hasZoomButton: zoom).document
    }

    // filePanel reports whether el is an open or save panel, which AppKit names by AXIdentifier.
    private static func filePanel(_ el: AXUIElement) -> Bool {
        WindowTraits(identifier: string(el, kAXIdentifierAttribute)).filePanel
    }

    // traitNames are the attributes traits asks for, in the order it reads the answers.
    private static let traitNames = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, kAXPositionAttribute, kAXSizeAttribute,
        "AXFullScreen", kAXZoomButtonAttribute, kAXIdentifierAttribute,
    ]

    // traits reads what decides whether el may be moved, and its zoom button, in one Accessibility
    // call. An attribute el lacks comes back as an error in its place and counts as missing. When the
    // app rejects the call as a whole, each attribute is asked on its own.
    static func traits(_ el: AXUIElement) -> (traits: WindowTraits, zoomButton: AXUIElement?) {
        var raw: CFArray?
        let values: [CFTypeRef?]
        if AXUIElementCopyMultipleAttributeValues(el, traitNames as CFArray, [], &raw) == .success,
            let list = raw as [AnyObject]?, list.count == traitNames.count
        {
            values = list.map { present($0) }
        } else {
            values = traitNames.map { value(el, $0) }
        }
        let zoom = values[6].flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeDowncast($0, to: AXUIElement.self) : nil
        }
        let traits = WindowTraits(
            role: values[0] as? String,
            subrole: values[1] as? String,
            minimized: values[2] as? Bool ?? false,
            fullScreen: values[5] as? Bool ?? false,
            identifier: values[7] as? String,
            hasZoomButton: zoom != nil,
            frame: frame(position: values[3], size: values[4])
        )
        return (traits, zoom)
    }

    // present returns v, or nil when it is the error or null a multiple-attribute read puts in place of
    // an attribute it could not read.
    private static func present(_ v: AnyObject) -> CFTypeRef? {
        if v is NSNull {
            return nil
        }
        if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(unsafeDowncast(v, to: AXValue.self)) == .axError {
            return nil
        }
        return v
    }

    // onScreen returns the on-screen windows at the normal layer, front-most first, with their
    // owners and frames.
    static func onScreen() -> [Listing] {
        let list =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                let id = entry[kCGWindowNumber as String] as? WindowID,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let b = entry[kCGWindowBounds as String] as? [String: Double]
            else { return nil }
            return (id, pid, Frame(x: b["X"] ?? 0, y: b["Y"] ?? 0, w: b["Width"] ?? 0, h: b["Height"] ?? 0))
        }
    }

    // onScreen returns the window with id as onScreen() would list it, nil when it would not: off
    // screen, not at the normal layer, or gone. It asks the window server for that window alone.
    static func onScreen(_ id: WindowID) -> Listing? {
        guard
            let entry = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]])?
                .first,
            entry[kCGWindowNumber as String] as? WindowID == id, entry[kCGWindowLayer as String] as? Int == 0,
            entry[kCGWindowIsOnscreen as String] as? Bool == true,
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
            let b = entry[kCGWindowBounds as String] as? [String: Double]
        else { return nil }
        return (id, pid, Frame(x: b["X"] ?? 0, y: b["Y"] ?? 0, w: b["Width"] ?? 0, h: b["Height"] ?? 0))
    }

    // id returns the window id of el.
    static func id(_ el: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        return axWindowID(el, &id) == .success && id != 0 ? WindowID(id) : nil
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
        frame(position: value(el, kAXPositionAttribute), size: value(el, kAXSizeAttribute))
    }

    // frame makes a frame from a position and a size value, nil when either is missing or not a point
    // and a size.
    private static func frame(position: CFTypeRef?, size: CFTypeRef?) -> Frame? {
        guard let p = position, let s = size,
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

// Windows is the Mac WindowStore. Its witnesses run on the main actor, where the engine lives.
extension Windows: @preconcurrency WindowStore {
    // scan reads every app when full, otherwise the apps PassPlan picks: those that woke or changed
    // since the last scan, the front app, and every app when a full read is due. A scan that is not
    // full takes the front app from the activation notifications, since an activation wakes a full
    // one.
    func scan(_ screens: Screens, full: Bool) -> Scan {
        let t = ProcessInfo.processInfo.systemUptime
        appWoke = appWoke.filter { t - $0.value < Pace.settleSeconds }
        echoes = echoes.filter { t - $0.value.at < Pace.settleSeconds }
        let echoed = echoes.mapValues(\.frame)
        let carry = PassPlan.carries(
            now: t, forced: full, lastFull: lastFull, lastScan: lastScan, woke: appWoke,
            placed: echoes.mapValues(\.at), listed: Set(listing.map(\.id)))
        let read = scan(screens, carry: carry, tracked: !full) { [self] listed, previous, slow, front in
            PassPlan.plan(
                now: t, forced: full, lastFull: lastFull, woke: appWoke,
                listed: listed, previous: previous, slow: slow, front: front, echoes: echoed)
        }
        if lastPlan == .full {
            lastFull = t
        }
        return Scan(windows: read.windows, focused: read.focused)
    }

    // move places the window. A move with no last frame is a hold or a step back and goes plain, as
    // the passes always moved; a placement from its last frame handles the app's Enhanced UI as
    // behavior says, and slides there when behavior animates.
    func move(_ id: WindowID, to frame: Frame, from: Frame?, behavior: Behaviors) {
        guard let from else {
            move(id, to: frame)
            return
        }
        echoes[id] = (frame, ProcessInfo.processInfo.systemUptime)
        if behavior.animate {
            slide(id, from: from, to: frame, enhancedUI: behavior.enhancedUI)
        } else {
            move(id, to: frame, enhancedUI: behavior.enhancedUI, from: from)
        }
    }

    // refused lists the windows Accessibility would not move or size.
    var refused: Set<WindowID> { refusedIDs }

    // alive lists the ids of every window on any space, and drops the elements of windows that are
    // gone. An off-screen window whose element this store holds counts only while the element still
    // answers. One it never held counts while the window server lists it.
    func alive() -> Set<WindowID> {
        let held = elements
        let ids = Self.living(Self.listed()) { id in held[id].map(Self.destroyed) ?? false }
        elements = elements.filter { ids.contains($0.key) }
        return ids
    }

    // ready reports whether moorings has Accessibility access.
    var ready: Bool { trusted }
}

// MacScreens is the Mac ScreenSource: the attached displays plus the notch and Stage Manager reads.
@MainActor
final class MacScreens: @preconcurrency ScreenSource {
    // current reads the attached screens.
    func current() -> Screens {
        Screens.current()
    }

    // quirks reads the notched screens, the screens showing the Stage Manager strip and its side.
    func quirks(_ screens: Screens) -> ScreenQuirks {
        let right = Self.stageOnRight()
        let notched = Set(NSScreen.screens.indices.filter { NSScreen.screens[$0].safeAreaInsets.top > 0 })
        return ScreenQuirks(notched: notched, staged: Self.staged(screens.full, right: right), stageOnRight: right)
    }

    // windowManager reads a Stage Manager setting from the WindowManager defaults.
    private static func windowManager(_ key: String) -> Bool? {
        UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: key) as? Bool
    }

    // stageOnRight reports whether the Stage Manager strip sits on the right: with the Dock on the
    // left, or with the Dock at the bottom in a right-to-left language.
    private static func stageOnRight() -> Bool {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": true
        case "right": false
        default: Locale.current.language.characterDirection == .rightToLeft
        }
    }

    // staged lists the screens showing the Stage Manager strip: Stage Manager is on, the strip is not
    // set to hide, and at least two WindowManager windows sit at the screen's strip edge. One alone
    // can be the window being dragged.
    private static func staged(_ full: [Frame], right: Bool) -> Set<Int> {
        guard windowManager("GloballyEnabled") == true, windowManager("AutoHide") != true else { return [] }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [Int: Int] = [:]
        for entry in list where entry[kCGWindowOwnerName as String] as? String == "WindowManager" {
            guard let b = entry[kCGWindowBounds as String] as? [String: Double],
                let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { continue }
            let rows = full.indices.filter { full[$0].y <= y && y + h <= full[$0].y + full[$0].h }
            let edge = { (i: Int) in right ? abs(full[i].x + full[i].w - (x + w)) : abs(x - full[i].x) }
            if let i = rows.min(by: { edge($0) < edge($1) }) {
                counts[i, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }
}
