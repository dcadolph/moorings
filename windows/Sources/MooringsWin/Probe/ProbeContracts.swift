import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeContracts runs the engine's contract suites on the Win32 adapters, against stand-in windows
// this exe opens with the stand probe, and prints each rule broken and the count.
func probeContracts(_ opts: ProbeOptions) -> Int32 {
    let host = WinHost(minAspect: opts.minAspect)
    let windows = WinWindows()
    let timers = WinTimers()
    let scheduler = timers.make()
    host.timers = { timers.fire($0) }
    var delivered: [String] = []
    let hotkeys = WinHotkeys { delivered.append($0) }
    host.hotkey = { hotkeys.fire($0) }
    let banner = BannerWindow(minAspect: opts.minAspect)
    var failures = WindowStoreContract.run(windows, host: host)
    failures += OverlayContract.run(WinFootprint(), store: windows, host: host)
    failures += NotifierContract.run(WinNotifier { banner.show($0, $1) }, store: windows, host: host)
    failures += SchedulerContract.run(scheduler, clock: WinClock(), host: host)
    failures += PointerContract.run(WinPointer(), host: host)
    failures += KeysContract.run(WinKeys(hotkeys), host: host, actions: { delivered })
    failures += LogContract.run(WinLog(), host: host)
    failures += TimersContract.run(timers, clock: WinClock(), host: host)
    failures += EventSourceContract.run(WinEvents(), store: windows, host: host)
    failures += ScreenSourceContract.run(WinScreens(), host: host)
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-contract-\(UUID().uuidString).json")
    host.choices = file
    failures += ChoicesStoreContract.run(Store(url: file), host: host)
    try? FileManager.default.removeItem(at: file)
    try? FileManager.default.removeItem(at: Store(url: file).aside)
    failures += ClockContract.run(WinClock(), host: host)
    failures += AppsContract.run(WinApps(), store: windows, host: host)
    failures += modifiersTable()
    for f in failures {
        print("contract failed: \(f)")
    }
    print("contracts: 13 suites, \(failures.count) failures")
    return failures.isEmpty ? 0 : 1
}

// modifiersTable checks Modifiers(down:) against virtual key sets, so a wrong code fails the contracts
// probe.
func modifiersTable() -> [ContractFailure] {
    let tests: [(vks: Set<Int32>, want: Modifiers)] = [
        // Test 0: Nothing down.
        ([], []),
        // Test 1: Left Alt is Option with no side bit.
        ([0x12, 0xA4], .option),
        // Test 2: Right Alt.
        ([0x12, 0xA5], [.option, .rightOption]),
        // Test 3: Left Win is Command.
        ([0x5B], .command),
        // Test 4: Right Win.
        ([0x5C], [.command, .rightCommand]),
        // Test 5: Right Ctrl.
        ([0x11, 0xA3], [.control, .rightControl]),
        // Test 6: Right Shift.
        ([0x10, 0xA1], [.shift, .rightShift]),
        // Test 7: Every side-free key.
        ([0x10, 0x11, 0x12, 0x5B], [.shift, .control, .option, .command]),
    ]
    return tests.enumerated().compactMap { i, test in
        let got = Modifiers { test.vks.contains($0) }
        return got == test.want
            ? nil
            : ContractFailure(
                rule: "virtual keys read as the same modifiers as the Mac",
                detail: "case \(i) want \(test.want.rawValue) got \(got.rawValue)")
    }
}

// WinHost is the Windows ContractHost: each window is a stand-in from this exe's stand probe in a
// process of its own, found by its process id, and waiting pumps this thread's messages.
final class WinHost: ContractHost {
    // timers runs a thread timer's work and reports whether the timer was its.
    var timers: (UINT_PTR) -> Bool = { _ in false }
    // hotkey is handed each WM_HOTKEY this thread receives while waiting.
    var hotkey: (WPARAM) -> Void = { _ in }
    // mouse is handed each thread message while waiting and reports whether it was the mouse hook's.
    var mouse: (MSG) -> Bool = { _ in false }
    // choices is the choices file touchChoices rewrites and spoilChoices writes, nil when the host has
    // none.
    var choices: URL?
    // shots is the folder the scenarios' pictures go into, nil when the host takes none.
    var shots: URL?
    // modifierKeys pairs each modifier with the virtual key press holds for it, Command as the left
    // Windows key.
    static let modifierKeys: [(Modifiers, WORD)] = [
        (.shift, 0x10), (.control, 0x11), (.option, 0x12), (.command, 0x5B),
    ]
    // minAspect is the ratio a monitor needs to count as ultrawide.
    private let minAspect: Double
    // stands lists the stand-in processes the host started.
    private var stands: [Process] = []
    // standIn is the lowercased path of the browser open launches in place of the stand probe, nil for
    // the stand probe's window.
    var standIn: String?
    // browsers lists the processes that own the browser windows the host opened.
    var browsers: [DWORD] = []
    // profiles lists the fresh browser profile folders the host made.
    var profiles: [URL] = []
    // first is the first stand-in window the host opened, whose border the minimum leaves out.
    private var first: HWND?

    // init builds a host whose screens count a monitor at least minAspect wide as ultrawide.
    init(minAspect: Double) {
        self.minAspect = minAspect
    }

    // minimum is the smallest visible frame a stand-in keeps: the smallest window Windows lets a
    // person size, less the invisible border that rect includes and the store's frames leave out.
    var minimum: (w: Double, h: Double)? {
        let track = (w: Double(GetSystemMetrics(SM_CXMINTRACK)), h: Double(GetSystemMetrics(SM_CYMINTRACK)))
        guard let first, let d = WinWindows.insets(first) else { return track }
        return (track.w - d.left - d.right, track.h - d.top - d.bottom)
    }

    // now is the tick count in seconds.
    var now: Double { App.now }

    // screens reads the monitors.
    func screens() -> Screens {
        Screens.current(minAspect: minAspect)
    }

    // open starts a stand-in process, or the stand-in browser when there is one, and returns its window
    // once it shows.
    func open() -> WindowID? {
        if let standIn {
            let found = openBrowser(standIn)
            if first == nil {
                first = found
            }
            return found.map(WinWindows.id)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: LoginItem.executable)
        p.arguments = ["--probe", "stand", "--seconds", "120"]
        do {
            try p.run()
        } catch {
            print("contracts: stand-in did not start: \(error)")
            return nil
        }
        stands.append(p)
        let pid = DWORD(p.processIdentifier)
        var found: HWND?
        _ = wait(until: now + 5) {
            found = WinWindows.topLevel().first {
                WinWindows.processID($0) == pid && WinWindows.className($0) == standClass && IsWindowVisible($0)
            }
            return found != nil
        }
        if first == nil {
            first = found
        }
        return found.map(WinWindows.id)
    }

    // openRefusing is nil: a window that refuses every move needs an elevated process.
    func openRefusing() -> WindowID? {
        nil
    }

    // knownApp is the stand-in browser's image path, else Notepad's, the identity the store gives
    // their windows.
    var knownApp: String? {
        if let standIn {
            return standIn
        }
        let root = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        return (root + "\\System32\\notepad.exe").lowercased()
    }

    // press injects key with its modifiers through SendInput and reports whether Windows took every
    // event.
    func press(_ key: GrabKey) -> Bool {
        guard let vk = WinHotkeys.keyCodes[key.key] else { return false }
        let vks = Self.modifierKeys.filter { key.modifiers.contains($0.0) }.map(\.1) + [WORD(vk)]
        return MooringsWin.press(vks) == UINT(vks.count * 2)
    }

    // nudge moves the window with id 8 pixels right and down from outside the store, as a drag would.
    func nudge(_ id: WindowID) -> Bool {
        guard let hwnd = WinWindows.hwnd(id) else { return false }
        var r = RECT()
        guard GetWindowRect(hwnd, &r) else { return false }
        let flags = UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)
        return SetWindowPos(hwnd, nil, r.left + 8, r.top + 8, 0, 0, flags)
    }

    // touchChoices moves the choices file's last write time a second later, as another program
    // writing it would, and reports whether it took.
    func touchChoices() -> Bool {
        guard let choices else { return false }
        let file = Store(url: choices)
        guard let time = file.writeTime() else { return false }
        return file.setWriteTime(time + 10_000_000)
    }

    // spoilChoices writes payload over the choices file, as a damaged disk or a hand edit would.
    func spoilChoices(_ payload: Data) -> Bool {
        guard let choices else { return false }
        return (try? payload.write(to: choices)) != nil
    }

    // choicesAside reads the file the store moved aside, nil when there is none.
    func choicesAside() -> Data? {
        choices.flatMap { try? Data(contentsOf: Store(url: $0).aside) }
    }

    // wait pumps this thread's messages, handing its thread timers to timers, until done or the
    // deadline.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        var msg = MSG()
        while !done() {
            guard now < deadline else { return false }
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if mouse(msg) {
                    continue
                }
                if msg.message == UINT(WM_TIMER), msg.hwnd == nil, timers(msg.wParam) {
                    continue
                }
                if msg.message == UINT(WM_HOTKEY), msg.hwnd == nil {
                    hotkey(msg.wParam)
                    continue
                }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }
            Sleep(5)
        }
        return true
    }

    // finish ends every stand-in process and every browser the host opened.
    func finish() {
        for p in stands where p.isRunning {
            p.terminate()
        }
        stands = []
        closeBrowsers()
        first = nil
    }
}
