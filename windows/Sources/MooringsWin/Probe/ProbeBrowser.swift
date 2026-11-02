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
    // process, so the window is found by its image path among the windows that were not there before.
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments =
            firefox
            ? ["-no-remote", "-new-instance", "-profile", profile.path, "about:blank"]
            : [
                "--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check",
                "--disable-sync", "--new-window", "about:blank",
            ]
        do {
            try p.run()
        } catch {
            print("scenarios: \(path) did not start: \(error)")
            return nil
        }
        browsers.append(DWORD(p.processIdentifier))
        var found: HWND?
        _ = wait(until: now + 20) {
            found = WinWindows.topLevel().first {
                !before.contains($0) && IsWindowVisible($0) && GetWindow($0, UINT(GW_OWNER)) == nil
                    && WinWindows.image(WinWindows.processID($0)) == path
            }
            return found != nil
        }
        guard let found else {
            print("scenarios: no \(path) window within 20 s")
            return nil
        }
        browsers.append(WinWindows.processID(found))
        settle(found)
        return found
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
        WinWindows().move(id, to: Frame(x: 50, y: 50, w: 100, h: 100))
        _ = wait(until: now + 0.5) { false }
        if let f = WinWindows().frame(id) {
            print("stand-in minimum: \(Int(f.w)) \(Int(f.h))")
        }
        finish()
    }
}
