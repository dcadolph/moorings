import AppKit

// Probe is the app the selftest, the Mac contracts and the bench move instead of a stock app. Its
// windows are plain titled windows with no document behind them, so it never asks to save, never
// reopens a window from before, and always quits when asked. It opens one window at launch, another
// on Command-N, on a Dock reopen with no window showing, or on the new-window distributed
// notification, and an open panel on Command-O. The hang distributed notification sleeps its main
// thread, so the selftest can check that a hung app does not stall Moorings. The latency
// notification times links that move its key window, for the bench.
@MainActor
final class Probe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // newWindow is the distributed notification that asks the probe for another window.
    static let newWindow = Notification.Name("com.dcadolph.moorings.probe.new-window")
    // hang is the distributed notification that sleeps the main thread for its seconds entry. With a
    // pid entry only the probe with that process identifier hangs.
    static let hang = Notification.Name("com.dcadolph.moorings.probe.hang")
    // hangSeconds is how long a hang lasts when the request names no seconds.
    static let hangSeconds = 6.0
    // size is the frame size each new window opens at.
    static let size = NSSize(width: 500, height: 350)
    // minimum is the smallest frame size a window may take.
    static let minimum = NSSize(width: 240, height: 160)

    // windows holds the open windows so they stay alive until closed.
    private var windows: [NSWindow] = []
    // count numbers the windows made, for their titles and their cascade.
    private var count = 0
    // latency is the latency run in progress, kept alive until it replies.
    private var latency: LatencyRun?

    // applicationWillFinishLaunching turns off window restore before AppKit reads it.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    // applicationDidFinishLaunching builds the menu, listens for new-window requests and opens the
    // launch window.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.menu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(requested), name: Self.newWindow, object: nil,
            suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(hung), name: Self.hang, object: nil, suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(timed), name: Latency.request, object: nil,
            suspensionBehavior: .deliverImmediately)
        newWindow(nil)
        NSApp.activate()
    }

    // applicationShouldHandleReopen opens a window when the probe is reopened with none showing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            newWindow(nil)
        }
        return true
    }

    // applicationShouldTerminateAfterLastWindowClosed keeps the probe running with no window, as a
    // document app does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // applicationSupportsSecureRestorableState is true so AppKit does not warn about restore, which
    // the probe never does.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // requested opens a window for a distributed new-window request.
    @objc private func requested(_ note: Notification) {
        newWindow(nil)
    }

    // hung sleeps the main thread, so the probe answers no event and no accessibility request until
    // the hang ends.
    @objc private func hung(_ note: Notification) {
        if let pid = note.userInfo?["pid"] as? String, pid != String(ProcessInfo.processInfo.processIdentifier) {
            return
        }
        let asked = (note.userInfo?["seconds"] as? String).flatMap(Double.init) ?? Self.hangSeconds
        Thread.sleep(forTimeInterval: min(max(asked, 0), 30))
    }

    // timed runs a latency request on the key window, or the newest one, and posts the result line.
    // A request while a run is in progress, or one with no window or a bad field, gets an error line.
    @objc private func timed(_ note: Notification) {
        let info = note.userInfo
        guard latency == nil, let n = (info?["n"] as? String).flatMap(Int.init), n > 0,
            let left = (info?["left"] as? String).flatMap(URL.init(string:)),
            let right = (info?["right"] as? String).flatMap(URL.init(string:)),
            let w = NSApp.keyWindow ?? windows.last
        else {
            Self.reply("error bad request, a run in progress, or no window")
            return
        }
        let run = LatencyRun(window: w)
        latency = run
        Task {
            let line = await run.run(n, left: left, right: right)
            latency = nil
            Self.reply(line)
        }
    }

    // reply posts a latency result line for the waiting command.
    private static func reply(_ line: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Latency.done, object: nil, userInfo: ["line": line], deliverImmediately: true)
    }

    // newWindow opens another window below and right of the last one and brings it forward.
    @objc func newWindow(_ sender: Any?) {
        count += 1
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isRestorable = false
        w.minSize = Self.minimum
        w.title = "Probe \(count)"
        w.delegate = self
        w.center()
        let step = CGFloat((count - 1) % 8) * 24
        w.setFrameOrigin(NSPoint(x: w.frame.minX + step, y: w.frame.minY - step))
        windows.append(w)
        w.makeKeyAndOrderFront(nil)
    }

    // openPanel shows an open panel as its own window, the way a document app's Open does.
    @objc func openPanel(_ sender: Any?) {
        NSOpenPanel().begin { _ in }
    }

    // windowWillClose drops the closing window.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        windows.removeAll { $0 === w }
    }

    // menu builds the app and File menus with the shortcuts the selftest presses.
    static func menu() -> NSMenu {
        let bar = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        bar.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = app
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open", action: #selector(openPanel(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        bar.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file
        return bar
    }
}

// cpuSeconds returns the user plus system CPU seconds of the process with pid, nil when it cannot be
// read. rusage_info_v4 counts in Mach absolute time units, which are not nanoseconds on Apple silicon.
func cpuSeconds(_ pid: pid_t) -> Double? {
    var info = rusage_info_v4()
    let err = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard err == 0 else { return nil }
    var base = mach_timebase_info_data_t()
    mach_timebase_info(&base)
    return Double(info.ri_user_time + info.ri_system_time) * Double(base.numer) / Double(base.denom) / 1e9
}

// The --cpu mode prints a process's CPU seconds for the bench and exits without opening a window.
let args = CommandLine.arguments
if args.count == 3, args[1] == "--cpu" {
    guard let pid = pid_t(args[2]), let secs = cpuSeconds(pid) else {
        FileHandle.standardError.write(Data("probe: cannot read the CPU time of pid \(args[2])\n".utf8))
        exit(1)
    }
    print(String(format: "%.6f", secs))
    exit(0)
}

// The --latency mode asks the running probe to time n left and right links and prints its line.
if args.count == 5, args[1] == "--latency" {
    guard let n = Int(args[2]), n > 0 else {
        FileHandle.standardError.write(Data("probe: --latency needs a positive count\n".utf8))
        exit(2)
    }
    exit(MainActor.assumeIsolated { Latency.ask(n: n, left: args[3], right: args[4]) })
}

MainActor.assumeIsolated {
    let probe = Probe()
    NSApplication.shared.delegate = probe
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}
