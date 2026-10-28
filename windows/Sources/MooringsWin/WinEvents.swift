import WinSDK

import MooringsCore
import MooringsEngine

// WinEvents is the Windows EventSource: the out-of-context window event hooks of a WinWatcher. The
// hooks cover every process, so no app ever waits for an observer. A move or birth of a window no
// pass listed is passed on only when a scan would describe it, and a move or size by a window's
// frame is handed to the drag closures as it begins and ends.
final class WinEvents: EventSource {
    // dragBegan is told the window a move or size by its frame began on.
    var dragBegan: (HWND) -> Void = { _ in }
    // dragEnded is told when that move or size ended.
    var dragEnded: () -> Void = {}

    // screens reads the displays a window must lie on to be described.
    private let screens: any ScreenSource
    // watcher holds the hooks.
    private lazy var watcher = WinWatcher { [unowned self] kind, hwnd in heard(kind, hwnd) }
    // deliver receives each event while started, nil while stopped.
    private var deliver: ((WindowEvent) -> Void)?
    // listed holds the windows the last pass listed.
    private var listed: Set<WindowID> = []

    // init builds a source that describes unlisted windows on the displays screens reads.
    init(screens: any ScreenSource = WinScreens()) {
        self.screens = screens
    }

    // waiting is false: the hooks need nothing from an app that just started.
    var waiting: Bool { false }

    // filters is false only in the events probe's negative control, which keeps every event.
    var filters: Bool {
        get { watcher.filters }
        set { watcher.filters = newValue }
    }

    // raw counts every event the hooks delivered.
    var raw: Int { watcher.raw }

    // passed counts the events the hooks passed on as top-level window events.
    var passed: Int { watcher.passed }

    // start installs the hooks and delivers each window event a pass acts on to deliver.
    func start(_ deliver: @escaping (WindowEvent) -> Void) {
        stop()
        self.deliver = deliver
        watcher.start()
    }

    // stop removes the hooks.
    func stop() {
        watcher.stop()
        deliver = nil
        listed = []
    }

    // watch keeps the windows in scan as listed and marks each as top-level, so a window listed before
    // its first event still reports its destroy.
    func watch(_ scan: Scan) {
        listed = Set(scan.windows.map(\.id))
        for w in scan.windows {
            if let hwnd = WinWindows.hwnd(w.id) {
                watcher.know(hwnd)
            }
        }
    }

    // heard hands a frame move or size to the drag closures, drops a geometry event for a window no
    // pass listed and no scan would describe, and delivers the rest.
    private func heard(_ kind: WinEvent, _ hwnd: HWND) {
        guard let deliver else { return }
        switch kind {
        case .moveSizeStart:
            dragBegan(hwnd)
        case .moveSizeEnd:
            dragEnded()
        default:
            break
        }
        let id = WinWindows.id(hwnd)
        if kind.geometry, !listed.contains(id) {
            guard WinWindows.describe(hwnd, screens: screens.current()) != nil else { return }
        }
        deliver(Self.event(kind, id))
    }

    // event names the window event kind is for id. A hide or the start of a frame move is a move,
    // since the window leaves or begins to leave where the last pass read it.
    static func event(_ kind: WinEvent, _ id: WindowID) -> WindowEvent {
        switch kind {
        case .show, .minimizeEnd: .shown(id)
        case .locationChange, .moveSizeStart, .moveSizeEnd, .minimizeStart, .hide: .moved(id)
        case .foreground: .focused(id)
        case .destroy: .destroyed(id)
        }
    }
}
