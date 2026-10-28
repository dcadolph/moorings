import MooringsCore
import MooringsEngine

// Insets is the invisible border a platform adds around a window's visible frame.
public struct Insets: Equatable, Sendable {
    // left is the border on the left edge.
    public var left: Double
    // top is the border on the top edge.
    public var top: Double
    // right is the border on the right edge.
    public var right: Double
    // bottom is the border on the bottom edge.
    public var bottom: Double

    // init builds insets from each edge.
    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    // grow returns f widened by the insets on every edge.
    public func grow(_ f: Frame) -> Frame {
        Frame(x: f.x - left, y: f.y - top, w: f.w + left + right, h: f.h + top + bottom)
    }
}

// FakeWindows is an in-memory WindowStore for engine tests and the contract suites.
public final class FakeWindows: WindowStore {
    // Window is one fake window.
    public struct Window: Equatable, Sendable {
        // id is the window's id.
        public var id: WindowID
        // bundle is the bundle ID of the window's app.
        public var bundle: String
        // frame is the window's frame.
        public var frame: Frame
        // isMain reports whether the window is its app's main window.
        public var isMain: Bool
        // minW is the narrowest the window lets itself be.
        public var minW: Double
        // minH is the shortest the window lets itself be.
        public var minH: Double
        // insets is the invisible border a move lands with.
        public var insets: Insets
        // refuses reports whether the window refuses every move.
        public var refuses: Bool
        // minimized reports whether the window is minimized.
        public var minimized: Bool
    }

    // Call is one call the store received.
    public enum Call: Equatable, Sendable {
        case scan(full: Bool)
        case move(WindowID, Frame, from: Frame?)
        case resize(WindowID, w: Double, h: Double)
        case position(WindowID, x: Double, y: Double)
        case raise(WindowID)
        case minimize(WindowID)
        case close(WindowID)
    }

    // windows lists the windows front to back.
    public private(set) var windows: [Window] = []
    // focusedID is the focused window's id, nil when none is.
    public var focusedID: WindowID?
    // calls records every call in order.
    public private(set) var calls: [Call] = []
    // refused lists the windows that refused a move.
    public private(set) var refused: Set<WindowID> = []
    // ready reports whether the store may act; tests turn it off to model a missing grant.
    public var ready = true
    // ignoresMinimum makes moves skip the minimum size, only for the contract's negative control.
    public var ignoresMinimum = false
    // nextID is the id the next added window gets.
    private var nextID: WindowID = 1

    // init builds an empty store.
    public init() {}

    // add puts a window in front of the others and returns its id.
    @discardableResult
    public func add(
        bundle: String, frame: Frame, isMain: Bool = true, minW: Double = 0, minH: Double = 0,
        insets: Insets = Insets(), refuses: Bool = false, focus: Bool = false
    ) -> WindowID {
        let id = nextID
        nextID += 1
        windows.insert(Window(id: id, bundle: bundle, frame: frame, isMain: isMain, minW: minW, minH: minH,
                              insets: insets, refuses: refuses, minimized: false), at: 0)
        if focus {
            focusedID = id
        }
        return id
    }

    // nudge moves a window the way a person would, outside the store, and records no call.
    public func nudge(_ id: WindowID, to frame: Frame) {
        guard let i = index(id) else { return }
        windows[i].frame = frame
    }

    // window returns the fake window with id, nil when it is gone.
    public func window(_ id: WindowID) -> Window? {
        index(id).map { windows[$0] }
    }

    // scan lists the windows that are not minimized and overlap a screen, front to back.
    public func scan(_ screens: Screens, full: Bool) -> Scan {
        calls.append(.scan(full: full))
        let infos = windows.compactMap { w -> WindowInfo? in
            guard !w.minimized, let i = screens.index(w.frame) else { return nil }
            return WindowInfo(id: w.id, bundle: w.bundle, frame: w.frame, onUltrawide: i == screens.ultrawide,
                              isMain: w.isMain)
        }
        return Scan(windows: infos, focused: infos.first { $0.id == focusedID })
    }

    // frame returns the window's frame, nil when it is gone.
    public func frame(_ id: WindowID) -> Frame? {
        window(id)?.frame
    }

    // move lands the window at frame grown by its insets and held at its minimum size. A window
    // that refuses keeps its frame and joins refused.
    public func move(_ id: WindowID, to frame: Frame, from: Frame?, behavior: Behaviors) {
        calls.append(.move(id, frame, from: from))
        guard let i = index(id) else { return }
        guard !windows[i].refuses else {
            refused.insert(id)
            return
        }
        var f = frame
        if !ignoresMinimum {
            f.w = max(f.w, windows[i].minW)
            f.h = max(f.h, windows[i].minH)
        }
        windows[i].frame = windows[i].insets.grow(f)
    }

    // resize sets the window's size, held at its minimum, and keeps its top-left corner.
    public func resize(_ id: WindowID, w: Double, h: Double) {
        calls.append(.resize(id, w: w, h: h))
        guard let i = index(id), !windows[i].refuses else { return }
        windows[i].frame.w = max(w, windows[i].minW)
        windows[i].frame.h = max(h, windows[i].minH)
    }

    // position moves the window's top-left corner to x, y and keeps its size. A window that refuses
    // keeps its frame and joins refused.
    public func position(_ id: WindowID, x: Double, y: Double) {
        calls.append(.position(id, x: x, y: y))
        guard let i = index(id) else { return }
        guard !windows[i].refuses else {
            refused.insert(id)
            return
        }
        windows[i].frame.x = x
        windows[i].frame.y = y
    }

    // raise moves the window to the front and focuses it.
    public func raise(_ id: WindowID) {
        calls.append(.raise(id))
        guard let i = index(id) else { return }
        var w = windows.remove(at: i)
        w.minimized = false
        windows.insert(w, at: 0)
        focusedID = id
    }

    // minimize hides the window from scans and drops its focus.
    public func minimize(_ id: WindowID) {
        calls.append(.minimize(id))
        guard let i = index(id) else { return }
        windows[i].minimized = true
        if focusedID == id {
            focusedID = nil
        }
    }

    // close removes the window.
    public func close(_ id: WindowID) {
        calls.append(.close(id))
        windows.removeAll { $0.id == id }
        if focusedID == id {
            focusedID = nil
        }
    }

    // alive lists the ids of every window that still exists, minimized or not.
    public func alive() -> Set<WindowID> {
        Set(windows.map(\.id))
    }

    // index returns the position of the window with id, nil when it is gone.
    private func index(_ id: WindowID) -> Int? {
        windows.firstIndex { $0.id == id }
    }
}
