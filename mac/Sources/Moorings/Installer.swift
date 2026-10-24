import AppKit
import os

import MooringsCore

// Installer moves a downloaded copy of Moorings into Applications on first launch, then ejects the
// disk image it came from and offers to move that image to the Trash.
@MainActor
final class Installer {
    // installedFromFlag is the launch argument that hands the image path to the relaunched copy.
    static let installedFromFlag = "--installed-from"
    // askedKey is the defaults key for the image paths already offered to the Trash.
    static let askedKey = "installerAsked"
    // declinedKey is the defaults key for the bundle paths whose move was declined.
    static let declinedKey = "moveDeclined"
    // destination is where Moorings is installed.
    static let destination = URL(fileURLWithPath: "/Applications/" + Install.appName)

    // logger writes to the unified log under the com.dcadolph.moorings subsystem.
    private let logger = Logger(subsystem: "com.dcadolph.moorings", category: "install")

    // offerMove asks to put a downloaded copy into Applications, and reports whether this copy is
    // quitting so the installed one can start.
    func offerMove() -> Bool {
        let bundle = Self.originalURL(Bundle.main.bundleURL)
        let place = Install.place(bundle: bundle.path, quarantined: Self.quarantined(bundle),
                                  images: Self.mountedImages(), home: NSHomeDirectory())
        var image: MountedImage?
        switch place {
        case .applications:
            return false
        case .diskImage(let mounted):
            image = mounted
        case .elsewhere:
            if declined.contains(bundle.path) {
                return false
            }
        }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move Moorings to Applications?"
        alert.informativeText = image == nil
            ? "Moorings is running from \(bundle.deletingLastPathComponent().lastPathComponent). "
                + "In Applications it is easy to find and starts at login."
            : "Moorings is running from its disk image. It will copy itself to Applications, start from "
                + "there, and eject the disk image."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            if image == nil {
                declined.append(bundle.path)
            }
            return false
        }
        do {
            try install(bundle, copy: image != nil)
        } catch {
            logger.error("install into Applications failed: \(error.localizedDescription, privacy: .public)")
            showDrag(bundle, image: image)
            return false
        }
        logger.notice("installed into Applications from \(bundle.path, privacy: .public)")
        relaunch(image)
        return true
    }

    // offerTrash ejects a disk image that still holds Moorings once the installed copy runs, and asks
    // once per image whether to move it to the Trash.
    func offerTrash() {
        let bundle = Self.originalURL(Bundle.main.bundleURL)
        guard Install.inApplications(bundle: bundle.path, home: NSHomeDirectory()) else { return }
        var targets = Install.holding(Self.mountedImages()) { FileManager.default.fileExists(atPath: $0) }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: Self.installedFromFlag), i + 1 < args.count,
           !targets.contains(where: { $0.image == args[i + 1] }) {
            targets.append(MountedImage(image: args[i + 1], mount: ""))
        }
        var asked = UserDefaults.standard.stringArray(forKey: Self.askedKey) ?? []
        for target in targets where !asked.contains(target.image) {
            asked.append(target.image)
            UserDefaults.standard.set(asked, forKey: Self.askedKey)
            if !target.mount.isEmpty {
                eject(target.mount)
            }
            let file = URL(fileURLWithPath: target.image)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Moorings is installed"
            alert.informativeText = "Move the installer \(file.lastPathComponent) to the Trash? You will not need it again."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Keep")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.recycle([file]) { [logger] _, error in
                    if let error {
                        logger.error("trash of the installer failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    // declined is the bundle paths whose move to Applications was declined.
    private var declined: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.declinedKey) }
    }

    // install copies or moves the bundle to Applications, quitting and trashing any copy already
    // there, and clears the download quarantine the user already approved by opening this copy.
    private func install(_ bundle: URL, copy: Bool) throws {
        let me = ProcessInfo.processInfo.processIdentifier
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where running.processIdentifier != me {
            running.terminate()
        }
        let files = FileManager.default
        if files.fileExists(atPath: Self.destination.path) {
            try files.trashItem(at: Self.destination, resultingItemURL: nil)
        }
        if copy {
            try files.copyItem(at: bundle, to: Self.destination)
        } else {
            try files.moveItem(at: bundle, to: Self.destination)
        }
        Self.run("/usr/bin/xattr", "-d", "-r", "com.apple.quarantine", Self.destination.path)
    }

    // relaunch starts the installed copy once this process has exited, handing it the image to eject,
    // and quits.
    private func relaunch(_ image: MountedImage?) {
        let script = "pid=$1; shift; while /bin/kill -0 \"$pid\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$@\""
        var args = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Self.destination.path]
        if let image {
            args += ["--args", Self.installedFromFlag, image.image]
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = args
        do {
            try task.run()
        } catch {
            logger.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([Self.destination])
        }
        NSApp.terminate(nil)
    }

    // showDrag falls back to the drag by hand when the copy cannot be written: it opens the disk
    // image window, or reveals the app, and says where to drag it.
    private func showDrag(_ bundle: URL, image: MountedImage?) {
        if let image {
            NSWorkspace.shared.open(URL(fileURLWithPath: image.mount))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([bundle])
        }
        let alert = NSAlert()
        alert.messageText = "Drag Moorings to Applications"
        alert.informativeText = image == nil
            ? "Moorings could not move itself. Drag it from the Finder window into your Applications folder."
            : "Moorings could not copy itself. Drag it onto the Applications folder in the window that opened."
        alert.runModal()
    }

    // eject detaches a disk image volume, retrying while the copy that ran from it lets go.
    private func eject(_ mount: String) {
        for attempt in 1...3 {
            if Self.run("/usr/bin/hdiutil", "detach", mount) == 0 {
                logger.notice("ejected \(mount, privacy: .public)")
                return
            }
            if attempt < 3 {
                Thread.sleep(forTimeInterval: 1)
            }
        }
        logger.error("eject of \(mount, privacy: .public) failed")
    }

    // originalURL undoes App Translocation, which runs a quarantined app from a random read-only
    // path, so the bundle's real place can be judged.
    static func originalURL(_ url: URL) -> URL {
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard url.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return url }
        let original = unsafeBitCast(symbol, to: Original.self)
        return original(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
    }

    // quarantined reports whether the bundle carries the download quarantine flag.
    static func quarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    // mountedImages lists the attached disk images and their volumes.
    static func mountedImages() -> [MountedImage] {
        let task = Process()
        let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return Install.images(hdiutilPlist: data)
    }

    // run runs a tool to completion and returns its exit status, or -1 when it cannot start.
    @discardableResult
    static func run(_ tool: String, _ args: String...) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
