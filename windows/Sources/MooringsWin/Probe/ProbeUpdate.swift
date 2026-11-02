import Foundation

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeUpdate runs one update check through WinUpdate against the release record at --url, as the
// version --current or the build's, and prints what the tray would show: "update <version>
// available" with the zip it would offer and the menu's first entry, "up to date", or "check
// failed" with the error. It then prints whether another check is due at once, which a failed
// check must not make true, so the app's loop waits out the schedule instead of retrying.
func probeUpdate(_ opts: ProbeOptions) -> Int32 {
    guard let url = opts.url else {
        print("check failed: --url is required")
        return 2
    }
    guard let current = ReleaseVersion(opts.current ?? version) else {
        print("check failed: version \(version) does not check")
        return 2
    }
    let done = DispatchSemaphore(value: 0)
    let checker = UpdateChecker(client: URLSessionClient(), current: current, platform: .windows, endpoint: url)
    let update = WinUpdate(checker: checker, launched: .distantPast) { result in
        switch result {
        case .success(nil): print("up to date")
        case .success: break
        case .failure(let error): print("check failed: \(error)")
        }
        done.signal()
    }
    update.start()
    done.wait()
    if let found = update.found {
        let name = found.zip?.lastPathComponent ?? "none"
        print("update \(found.tag.dropFirst(found.tag.hasPrefix("v") ? 1 : 0)) available zip \(name)")
        let first = Tray.menu(choices: Choices(), running: [], atLogin: false, update: found).first
        print("menu first: \(first?.title ?? "none")")
    }
    print("due again: \(update.due())")
    return 0
}
