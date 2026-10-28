import AppKit
import os

import MooringsEngine

// MacApps is the Mac Apps: names from the running app or its bundle, and opens through open(1) the
// way a Dock click does.
@MainActor
final class MacApps: @preconcurrency Apps {
    // logger writes why an open failed.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "anchors")

    // name returns the display name of the running app with bundle, else the installed app's name, else
    // the bundle.
    func name(_ bundle: String) -> String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return url.deletingPathExtension().lastPathComponent
    }

    // open opens the app with bundle, which launches it or asks a running app with no window for a new
    // one. A background open leaves the front app in front. It returns false when no app has bundle
    // or open(1) cannot start.
    func open(_ bundle: String, background: Bool, target: String?) -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil else {
            logger.notice("open \(bundle, privacy: .public): no app has that bundle id")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = (background ? ["-g"] : []) + ["-b", bundle] + (target.map { [$0] } ?? [])
        do {
            try task.run()
        } catch {
            logger.error("open \(bundle, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }
}
