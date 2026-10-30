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
        let place = Install.place(
            bundle: bundle.path, quarantined: Self.quarantined(bundle),
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
        if let image {
            let name = URL(fileURLWithPath: image.image).lastPathComponent
            alert.messageText = "Install Moorings?"
            alert.informativeText =
                "Moorings will copy itself to Applications, start from there, "
                + "eject the disk image, and move \(name) to the Trash."
            alert.addButton(withTitle: "Install")
        } else {
            let folder = bundle.deletingLastPathComponent().lastPathComponent
            alert.messageText = "Move Moorings to Applications?"
            alert.informativeText =
                "Moorings is running from \(folder). "
                + "In Applications it is easy to find and starts at login."
            alert.addButton(withTitle: "Move to Applications")
        }
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

    // offerTrash ejects a disk image that still holds Moorings once the installed copy runs. It
    // trashes the image the install was okayed from without asking again, and asks once per image
    // about any other.
    func offerTrash() {
        let bundle = Self.originalURL(Bundle.main.bundleURL)
        guard Install.inApplications(bundle: bundle.path, home: NSHomeDirectory()) else { return }
        var targets = Install.holding(Self.mountedImages()) { FileManager.default.fileExists(atPath: $0) }
        let args = ProcessInfo.processInfo.arguments
        var okayed: String?
        if let i = args.firstIndex(of: Self.installedFromFlag), i + 1 < args.count {
            okayed = args[i + 1]
            if !targets.contains(where: { $0.image == args[i + 1] }) {
                targets.append(MountedImage(image: args[i + 1], mount: ""))
            }
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
            if target.image != okayed {
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "Moorings is installed"
                alert.informativeText =
                    "Move the installer \(file.lastPathComponent) to the "
                    + "Trash? You will not need it again."
                alert.addButton(withTitle: "Move to Trash")
                alert.addButton(withTitle: "Keep")
                guard alert.runModal() == .alertFirstButtonReturn else { continue }
            }
            NSWorkspace.shared.recycle([file]) { [logger] _, error in
                if let error {
                    let reason = error.localizedDescription
                    logger.error("trash of the installer failed: \(reason, privacy: .public)")
                } else {
                    logger.notice("moved the installer \(file.path, privacy: .public) to the Trash")
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
        for running in NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
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
        let extra = image.map { ["--args", Self.installedFromFlag, $0.image] } ?? []
        do {
            try Relaunch.start(Relaunch.Plan(bundle: Self.destination), extra: extra)
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
        alert.informativeText =
            image == nil
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

// Relaunch starts a bundle once this process has exited. With a launch marker it also waits for the
// new build to say it started and, when it never does, puts the previous bundle back and starts that.
enum Relaunch {
    // script is the detached helper. It takes the waited pid, the opener, the bundle, the previous
    // bundle, where to park a failed bundle, the marker, the build the marker must hold, the seconds
    // to wait, then the opener's extra arguments. An empty marker skips the wait and the rollback.
    static let script = """
        pid=$1 opener=$2 bundle=$3 previous=$4 failed=$5 marker=$6 build=$7 wait=$8
        shift 8
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        "$opener" "$bundle" "$@" &
        [ -n "$marker" ] || exit 0
        n=$((wait * 5))
        while [ "$n" -gt 0 ]; do
            if [ -f "$marker" ]; then
                got=
                read -r got < "$marker"
                [ "$got" = "$build" ] && exit 0
            fi
            /bin/sleep 0.2
            n=$((n - 1))
        done
        if [ -f "$marker.pid" ]; then
            b= p=
            read -r b p < "$marker.pid"
            [ "$b" = "$build" ] && [ -n "$p" ] && /bin/kill "$p" 2>/dev/null && /bin/sleep 1
        fi
        /bin/mv "$bundle" "$failed" && /bin/mv "$previous" "$bundle" && exec "$opener" "$bundle"
        """

    // Plan names what the helper starts and how it rolls back.
    struct Plan {
        // bundle is what the helper starts.
        var bundle: URL
        // previous is the bundle put back when the new one never writes the marker.
        var previous: URL?
        // failed is where a bundle that never wrote the marker is parked.
        var failed: URL?
        // marker is the file the new build writes its build number to once it has started.
        var marker: URL?
        // build is the build number the marker must hold.
        var build = ""
        // wait is how many seconds the helper waits for the marker.
        var wait = 30
        // opener starts the bundle. /usr/bin/open in the app, a shell in tests.
        var opener = "/usr/bin/open"
        // pid is the process the helper waits on before it starts the bundle.
        var pid = ProcessInfo.processInfo.processIdentifier
    }

    // arguments returns the helper's command line for the plan.
    static func arguments(_ plan: Plan, extra: [String] = []) -> [String] {
        [
            "-c", script, "sh", String(plan.pid), plan.opener, plan.bundle.path, plan.previous?.path ?? "",
            plan.failed?.path ?? "", plan.marker?.path ?? "", plan.build, String(plan.wait),
        ] + extra
    }

    // start runs the helper detached and returns at once.
    @discardableResult
    static func start(_ plan: Plan, extra: [String] = []) throws -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = arguments(plan, extra: extra)
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        return task
    }
}
