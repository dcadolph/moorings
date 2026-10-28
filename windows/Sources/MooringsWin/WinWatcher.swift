import WinSDK

import MooringsCore

// WinEvent is a window event the passes act on.
enum WinEvent: DWORD, CaseIterable {
    case foreground = 0x0003
    case moveSizeStart = 0x000A
    case moveSizeEnd = 0x000B
    case minimizeStart = 0x0016
    case minimizeEnd = 0x0017
    case destroy = 0x8001
    case show = 0x8002
    case hide = 0x8003
    case locationChange = 0x800B

    // geometry reports whether the event tells of a window's place or birth, which is news only for
    // a window a pass keeps or would keep.
    var geometry: Bool { self == .locationChange || self == .show }

    // ranges are the two event spans hooked: system events and object events.
    static let ranges: [(DWORD, DWORD)] = [(0x0003, 0x0017), (0x8001, 0x800B)]
}

// WinWatcher hooks the window events of every process out of context and calls its handler for
// each event of a top-level window. The hooks deliver on the thread that set them, through its
// message loop.
final class WinWatcher {
    // handler runs on each kept event with the event and the window.
    let handler: (WinEvent, HWND) -> Void
    // filters is false only in the events probe's negative control, which keeps every event.
    var filters = true
    // raw counts every event the hooks deliver.
    private(set) var raw = 0
    // passed counts the events passed on to the handler.
    private(set) var passed = 0
    // hooks holds the installed hooks.
    private var hooks: [HWINEVENTHOOK] = []
    // known holds the top-level windows an event or know named, since a destroyed window has no
    // ancestor left to prove it was one.
    private var known: Set<HWND> = []

    // init builds a watcher that calls handler on each kept event.
    init(handler: @escaping (WinEvent, HWND) -> Void) {
        self.handler = handler
    }

    // start installs the hooks. Only one watcher runs at a time.
    func start() {
        guard hooks.isEmpty else { return }
        WinWatcher.current = self
        for (low, high) in WinEvent.ranges {
            let flags = DWORD(WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS)
            if let hook = SetWinEventHook(
                low, high, nil,
                { _, event, hwnd, idObject, idChild, _, _ in
                    WinWatcher.current?.deliver(event, hwnd, idObject, idChild)
                }, 0, 0, flags)
            {
                hooks.append(hook)
            }
        }
    }

    // stop removes the hooks.
    func stop() {
        for hook in hooks {
            _ = UnhookWinEvent(hook)
        }
        hooks = []
        known = []
        WinWatcher.current = nil
    }

    // know records hwnd as a top-level window, so its destroy is passed on.
    func know(_ hwnd: HWND) {
        known.insert(hwnd)
    }

    // current is the running watcher, which the hook callback reaches since it cannot capture.
    nonisolated(unsafe) static var current: WinWatcher?

    // objectWindow is OBJID_WINDOW and childSelf is CHILDID_SELF: the event is about the window
    // itself, not a control, the caret, or the cursor inside it.
    static let objectWindow: LONG = 0, childSelf: LONG = 0
    // root is GA_ROOT, which GetAncestor answers with the top-level window.
    static let root = UINT(2)

    // deliver counts an event and passes it on when it is about a top-level window itself. A destroy
    // passes only for a window known to be top-level, which it then forgets.
    private func deliver(_ event: DWORD, _ hwnd: HWND?, _ idObject: LONG, _ idChild: LONG) {
        raw += 1
        guard let hwnd, let kind = WinEvent(rawValue: event) else { return }
        if filters {
            guard idObject == Self.objectWindow, idChild == Self.childSelf else { return }
            if kind == .destroy {
                guard known.remove(hwnd) != nil else { return }
            } else {
                guard GetAncestor(hwnd, Self.root) == hwnd else { return }
                known.insert(hwnd)
            }
        }
        passed += 1
        handler(kind, hwnd)
    }
}
