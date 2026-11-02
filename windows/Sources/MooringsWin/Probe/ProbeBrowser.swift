import Foundation
import WinSDK

import MooringsCore

// firefoxPrefs keeps a fresh Firefox profile from opening anything but its window: no default browser
// question, no welcome page, no data reporting notice.
let firefoxPrefs = """
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.aboutwelcome.enabled", false);
    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("startup.homepage_welcome_url", "");
    user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
    user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
    """

extension WinHost {
    // openBrowser starts the browser at path with a fresh profile and returns its new window once it
    // shows and holds still, nil when none shows within 20 s. A browser may hand its window to another
    // process, so the window is found by its image path among the windows that were not there before,
    // and it must be one the store reads, which passes over a captionless handoff dialog.
    func openBrowser(_ path: String) -> HWND? {
        let profile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "moorings-browser-\(UUID().uuidString)")
        let firefox = path.hasSuffix("\\firefox.exe")
        do {
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            if firefox {
                try Data(firefoxPrefs.utf8).write(to: profile.appendingPathComponent("user.js"))
            }
        } catch {
            print("scenarios: no browser profile: \(error)")
            return nil
        }
        profiles.append(profile)
        let before = Set(WinWindows.topLevel())
        let args =
            firefox
            ? ["-no-remote", "-new-instance", "-profile", profile.path, "about:blank"]
            : [
                "--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check",
                "--disable-sync", "--new-window", "about:blank",
            ]
        guard let pid = launch(path, args) else { return nil }
        browsers.append(pid)
        var found: HWND?
        _ = wait(until: now + 20) {
            found = WinWindows.topLevel().first {
                !before.contains($0) && IsWindowVisible($0) && GetWindow($0, UINT(GW_OWNER)) == nil
                    && WinWindows.image(WinWindows.processID($0)) == path
                    && WinWindows.describe($0, screens: screens()) != nil
            }
            return found != nil
        }
        guard let found else {
            for hwnd in WinWindows.topLevel()
            where !before.contains(hwnd) && WinWindows.image(WinWindows.processID(hwnd)) == path {
                describeStandIn(hwnd, "never read")
            }
            print("scenarios: no \(path) window within 20 s")
            return nil
        }
        browsers.append(WinWindows.processID(found))
        settle(found)
        return found
    }

    // launch starts path with args and no inherited handles, so a browser helper that outlives the
    // probe cannot hold the probe's output pipe open, and returns the process id, nil when it fails.
    func launch(_ path: String, _ args: [String]) -> DWORD? {
        let line = ([path] + args).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        var command = Array(line.utf16) + [0]
        var startup = STARTUPINFOW()
        startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
        var info = PROCESS_INFORMATION()
        let started = command.withUnsafeMutableBufferPointer { buffer in
            CreateProcessW(nil, buffer.baseAddress, nil, nil, false, 0, nil, nil, &startup, &info)
        }
        guard started else {
            print("scenarios: \(path) did not start: error \(GetLastError())")
            return nil
        }
        _ = CloseHandle(info.hThread)
        _ = CloseHandle(info.hProcess)
        return info.dwProcessId
    }

    // settle waits up to 5 s for hwnd's frame to hold for 1 s, since a browser sizes its first window
    // after it shows.
    func settle(_ hwnd: HWND) {
        var last = WinWindows.bounds(hwnd)
        var since = now
        _ = wait(until: now + 5) {
            let f = WinWindows.bounds(hwnd)
            if f != last {
                last = f
                since = now
            }
            return now - since >= 1
        }
    }

    // closeBrowsers ends every browser process the host started and removes their profiles. A profile
    // still held by a closing process stays in the temporary folder.
    func closeBrowsers() {
        for pid in Set(browsers) {
            guard let process = OpenProcess(DWORD(PROCESS_TERMINATE), false, pid) else { continue }
            _ = TerminateProcess(process, 0)
            _ = CloseHandle(process)
        }
        browsers = []
        guard !profiles.isEmpty else { return }
        _ = wait(until: now + 1) { false }
        for profile in profiles {
            try? FileManager.default.removeItem(at: profile)
        }
        profiles = []
    }

    // measureStandIn opens one stand-in browser window, prints the insets its rect reaches past its
    // visible frame and the smallest frame it takes when sized to 100 by 100, then closes it. The
    // insets say whether the --no-delta control can fail on it; the minimum says which targets it can
    // reach.
    func measureStandIn() {
        guard let id = open(), let hwnd = WinWindows.hwnd(id) else {
            print("stand-in: no window")
            return
        }
        if let d = WinWindows.insets(hwnd) {
            print("stand-in insets: \(Int(d.left)) \(Int(d.top)) \(Int(d.right)) \(Int(d.bottom))")
        }
        describeStandIn(hwnd, "at once")
        _ = wait(until: now + 2) { false }
        describeStandIn(hwnd, "after 2 s")
        WinWindows().move(id, to: Frame(x: 50, y: 50, w: 100, h: 100))
        _ = wait(until: now + 0.5) { false }
        if let f = WinWindows().frame(id) {
            print("stand-in minimum: \(Int(f.w)) \(Int(f.h))")
            standInMinimum = (f.w, f.h)
        }
        finish()
    }

    // describeStandIn prints the bits the store reads to decide whether hwnd is a movable window, and
    // whether it is one, so a browser the store never reads names its reason in the log.
    func describeStandIn(_ hwnd: HWND, _ when: String) {
        let style = GetWindowLongPtrW(hwnd, GWL_STYLE)
        let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
        let caption = style & LONG_PTR(WS_CAPTION) == LONG_PTR(WS_CAPTION)
        let tool = exStyle & LONG_PTR(WS_EX_TOOLWINDOW) != 0
        let framed = WinWindows.bounds(hwnd) != nil
        let read = WinWindows.describe(hwnd, screens: screens()) != nil
        print(
            "stand-in window \(when): class \(WinWindows.className(hwnd)) caption \(caption) tool \(tool)"
                + " cloaked \(WinWindows.cloaked(hwnd)) iconic \(IsIconic(hwnd)) bounds \(framed)"
                + " app \(WinWindows.bundle(hwnd) ?? "none") read \(read)")
    }
}
