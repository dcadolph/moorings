import CryptoKit
import Foundation

import MooringsCore

// Downloader fetches a URL into a local file.
protocol Downloader: Sendable {
    // download writes the body of url to file and refuses a body over limit bytes.
    func download(_ url: URL, to file: URL, limit: Int) async throws
}

// Trust judges an unpacked bundle and returns the step that refused it, or nil when it may install.
protocol Trust: Sendable {
    // verify checks the bundle against the release's version, such as 1.16.0.
    func verify(bundle: URL, version: String) -> UpdateVerdict?
}

// DownloadError names why a download stopped short of a file.
enum DownloadError: Error, Equatable {
    // status is a response other than 200.
    case status(Int)
    // tooLarge is a body over the limit.
    case tooLarge
}

// URLSessionDownloader downloads with URLSession, writing the body as it arrives so the limit holds
// before the file grows past it.
struct URLSessionDownloader: Downloader {
    // download writes the body of url to file and refuses a body over limit bytes.
    func download(_ url: URL, to file: URL, limit: Int) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw DownloadError.status(status)
        }
        guard response.expectedContentLength <= Int64(limit) else {
            throw DownloadError.tooLarge
        }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let out = try FileHandle(forWritingTo: file)
        defer { try? out.close() }
        var chunk = Data()
        chunk.reserveCapacity(1 << 16)
        var total = 0
        for try await byte in bytes {
            total += 1
            guard total <= limit else {
                throw DownloadError.tooLarge
            }
            chunk.append(byte)
            if chunk.count == 1 << 16 {
                try out.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        try out.write(contentsOf: chunk)
    }
}

// CodeTrustCheck is the Mac's Trust: CodeTrust's checks against the running app.
struct CodeTrustCheck: Trust {
    // current is the running version.
    let current: ReleaseVersion
    // running is the running app's designated requirement, nil when the app is unsigned.
    let running: String?

    // verify runs CodeTrust's checks on the bundle.
    func verify(bundle: URL, version: String) -> UpdateVerdict? {
        CodeTrust.verify(bundle: bundle, version: version, current: current, running: running)
    }
}

// UpdateState is where an update stands.
enum UpdateState: Equatable, Sendable {
    // idle is no update under way.
    case idle
    // downloading is the release of the tag being fetched and verified.
    case downloading(String)
    // verified is the release of the tag staged and waiting for a quiet moment.
    case verified(String)
    // installing is the release of the tag being swapped in.
    case installing(String)
    // refused is the release of the tag turned down at the named step.
    case refused(UpdateVerdict, String)

    // status is the state as moorings://status prints it.
    var status: String {
        switch self {
        case .idle: "idle"
        case .downloading(let tag): "downloading \(tag)"
        case .verified(let tag): "verified \(tag)"
        case .installing(let tag): "installing \(tag)"
        case .refused(let step, let tag): "refused(\(step.rawValue)) \(tag)"
        }
    }

    // busy reports whether an update is past its check and not yet settled.
    var busy: Bool {
        switch self {
        case .downloading, .verified, .installing: true
        case .idle, .refused: false
        }
    }
}

// Updater checks for a newer release, downloads and verifies it, stages it, and hands it to install at
// the first quiet moment. Every refusal names its step, and a tag is tried at most once per launch.
@MainActor
final class Updater {
    // zipLimit caps the release zip.
    static let zipLimit = 100 << 20
    // sumsLimit caps SHA256SUMS.
    static let sumsLimit = 64 << 10
    // quietEvery is how often a staged update looks for a quiet moment.
    static let quietEvery: TimeInterval = 5
    // appName is the bundle a release zip holds.
    nonisolated static let appName = "Moorings.app"

    // client asks GitHub for the latest release.
    let client: any HTTPClient
    // downloader fetches the release assets.
    let downloader: any Downloader
    // trust judges the unpacked bundle.
    let trust: any Trust
    // current is the running version.
    let current: ReleaseVersion
    // bundle is the running bundle the update replaces.
    let bundle: URL
    // cache is the folder downloads are staged in. Each fetch empties it first.
    let cache: URL
    // freeSpace returns the bytes free on the volume holding a folder.
    var freeSpace: (URL) -> Int64 = Updater.available
    // log writes one line per step.
    var log: (String) -> Void = { _ in }
    // changed is told each time state or release changes.
    var changed: () -> Void = {}
    // quiet reports whether now is a good moment to relaunch.
    var quiet: () -> Bool = { false }
    // allowed reports whether the owner currently wants staged updates installed on their own.
    var allowed: () -> Bool = { true }
    // install swaps the staged bundle of the tag in and relaunches.
    var install: (URL, String) -> Void = { _, _ in }

    // state is where the update stands.
    private(set) var state: UpdateState = .idle
    // release is the newer release the last check found, nil when none.
    private(set) var release: ReleaseInfo?
    // staged is the verified bundle waiting to install.
    private(set) var staged: URL?
    // tried holds the tags already fetched or skipped, so none is fetched twice.
    private var tried: Set<String>
    // timer looks for a quiet moment while an update is staged.
    private var timer: Timer?

    // init builds an updater for the running version and bundle. skip lists tags never to fetch, such
    // as one that already failed to start.
    init(
        client: any HTTPClient, downloader: any Downloader, trust: any Trust, current: ReleaseVersion, bundle: URL,
        cache: URL, skip: Set<String> = []
    ) {
        self.client = client
        self.downloader = downloader
        self.trust = trust
        self.current = current
        self.bundle = bundle
        self.cache = cache
        tried = skip
    }

    // check asks GitHub for a newer release when automatic checks are on or the check is forced, and
    // with install on fetches, verifies and stages it. It returns the newer release, nil when none.
    @discardableResult
    func check(automatic: Bool, install: Bool, forced: Bool = false) async throws -> ReleaseInfo? {
        guard automatic || forced, !state.busy else {
            return release
        }
        let found = try await UpdateChecker(client: client, current: current).check()
        release = found
        changed()
        if let found, install {
            await fetch(found)
        }
        return found
    }

    // fetch downloads the release, checks it against SHA256SUMS, unpacks it, verifies the bundle and
    // stages it. A download that fails in transit leaves the tag free for the next check.
    func fetch(_ release: ReleaseInfo) async {
        let tag = release.tag
        guard !tried.contains(tag), !state.busy else {
            return
        }
        tried.insert(tag)
        guard let version = ReleaseVersion(tag), version > current else {
            return refuse(.metadata, tag)
        }
        log("metadata \(tag)")
        guard let zip = release.zip, let sums = release.checksums else {
            return refuse(.assets, tag)
        }
        guard Self.replaceable(bundle) else {
            return refuse(.location, tag)
        }
        set(.downloading(tag))
        let files = FileManager.default
        let dir = cache.appendingPathComponent(tag, isDirectory: true)
        try? files.removeItem(at: cache)
        do {
            try files.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return refuse(.space, tag)
        }
        let zipFile = dir.appendingPathComponent(zip.lastPathComponent)
        let sumsFile = dir.appendingPathComponent("SHA256SUMS")
        do {
            try await downloader.download(sums, to: sumsFile, limit: Self.sumsLimit)
            try await downloader.download(zip, to: zipFile, limit: Self.zipLimit)
        } catch is DownloadError {
            return refuse(.assets, tag)
        } catch {
            log("download of \(tag) failed: \(error.localizedDescription)")
            tried.remove(tag)
            return set(.idle)
        }
        log("assets 2")
        let size = ((try? files.attributesOfItem(atPath: zipFile.path))?[.size] as? Int64) ?? 0
        guard min(freeSpace(bundle.deletingLastPathComponent()), freeSpace(dir)) >= 2 * size else {
            return refuse(.space, tag)
        }
        let trust = self.trust
        let name = String(tag.dropFirst(tag.hasPrefix("v") ? 1 : 0))
        let outcome = await Task.detached {
            Self.verify(zip: zipFile, sums: sumsFile, into: dir, version: name, trust: trust)
        }.value
        switch outcome {
        case .refused(let step):
            refuse(step, tag)
        case .staged(let app):
            log("checksum ok")
            for step in [UpdateVerdict.signature, .requirement, .notarization, .plist] {
                log("\(step.rawValue) ok")
            }
            staged = app
            set(.verified(tag))
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: Self.quietEvery, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer?.tolerance = 1
        }
    }

    // tick installs the staged update when now is quiet.
    func tick() {
        guard case .verified = state, allowed(), quiet() else {
            return
        }
        installNow()
    }

    // discardStaged drops a verified update that is waiting for a quiet moment. It does nothing in
    // any other state.
    func discardStaged() {
        guard case .verified(let tag) = state else {
            return
        }
        stopWaiting()
        staged = nil
        log("discarded \(tag)")
        set(.idle)
    }

    // installNow hands the staged update to install without waiting for a quiet moment.
    func installNow() {
        guard case .verified(let tag) = state, let staged else {
            return
        }
        stopWaiting()
        set(.installing(tag))
        log("swap \(tag)")
        install(staged, tag)
    }

    // refuse records that the release of the tag was turned down at step.
    func refuse(_ step: UpdateVerdict, _ tag: String) {
        stopWaiting()
        staged = nil
        log("refused \(tag) at \(step.rawValue)")
        set(.refused(step, tag))
    }

    // stopWaiting stops looking for a quiet moment.
    private func stopWaiting() {
        timer?.invalidate()
        timer = nil
    }

    // set moves to state and tells changed.
    private func set(_ next: UpdateState) {
        state = next
        changed()
    }

    // Outcome is what verify found.
    enum Outcome: Sendable, Equatable {
        // staged is the unpacked bundle that passed every check.
        case staged(URL)
        // refused is the step that turned the download down.
        case refused(UpdateVerdict)
    }

    // verify checks the zip against SHA256SUMS, unpacks it into dir and runs trust on the bundle.
    nonisolated static func verify(zip: URL, sums: URL, into dir: URL, version: String, trust: any Trust) -> Outcome {
        guard let text = try? String(contentsOf: sums, encoding: .utf8), let hex = sha256(zip),
            Checksums.matches(hex, name: zip.lastPathComponent, in: Checksums.parse(text))
        else {
            return .refused(.checksum)
        }
        let out = dir.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        let app = out.appendingPathComponent(appName)
        guard unzip(zip, into: out),
            FileManager.default.fileExists(atPath: app.path)
        else {
            return .refused(.assets)
        }
        if let step = trust.verify(bundle: app, version: version) {
            return .refused(step)
        }
        return .staged(app)
    }

    // unzip unpacks the zip into folder with ditto and reports whether ditto succeeded.
    nonisolated static func unzip(_ zip: URL, into folder: URL) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zip.path, folder.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else {
            return false
        }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // sha256 returns the lowercase hex digest of the file, or nil when it cannot be read.
    nonisolated static func sha256(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // replaceable reports whether the bundle can be swapped in place: an app bundle outside App
    // Translocation in a folder this user can write.
    nonisolated static func replaceable(_ bundle: URL) -> Bool {
        bundle.pathExtension == "app" && !bundle.path.contains("/AppTranslocation/")
            && access(bundle.deletingLastPathComponent().path, W_OK) == 0
    }

    // available returns the bytes free for important use on the volume holding the folder, or zero
    // when it cannot be read.
    nonisolated static func available(_ folder: URL) -> Int64 {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // swap puts staged in place of bundle, keeps the old bundle at previous and returns where the old
    // bundle ended up: previous, or beside the bundle when it could not be moved there.
    nonisolated static func swap(bundle: URL, staged: URL, previous: URL) throws -> URL {
        let files = FileManager.default
        let backupName = "Moorings.previous.app"
        let beside = bundle.deletingLastPathComponent().appendingPathComponent(backupName)
        try? files.removeItem(at: beside)
        _ = try files.replaceItemAt(
            bundle, withItemAt: staged, backupItemName: backupName,
            options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
        do {
            try? files.removeItem(at: previous)
            try files.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.moveItem(at: beside, to: previous)
            return previous
        } catch {
            return beside
        }
    }

    // unswap puts the backup back at the bundle path and removes the bundle the swap installed.
    nonisolated static func unswap(bundle: URL, backup: URL) throws {
        _ = try FileManager.default.replaceItemAt(bundle, withItemAt: backup)
    }
}

// LaunchMarker is how a build says it started, and how the next launch learns the last one ended
// without Quit. The relaunch helper reads it to decide whether to roll back.
struct LaunchMarker {
    // folder holds the marker files.
    let folder: URL

    // marker holds the build number of the last launch that finished starting.
    var marker: URL { folder.appendingPathComponent("launched") }
    // starting holds the build number and pid of a launch under way.
    var starting: URL { folder.appendingPathComponent("launched.pid") }
    // quitNote is present when the last run ended through Quit.
    var quitNote: URL { folder.appendingPathComponent("quit") }

    // begin records the build and pid of a launch under way, and reports whether the last run of the
    // same build ended without Quit.
    func begin(build: String, pid: Int32) -> Bool {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        let last = (try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let crashed = last == build && !files.fileExists(atPath: quitNote.path)
        try? "\(build) \(pid)\n".write(to: starting, atomically: true, encoding: .utf8)
        return crashed
    }

    // finish records that the build finished starting and clears the last run's quit note.
    func finish(build: String) {
        try? FileManager.default.removeItem(at: quitNote)
        try? "\(build)\n".write(to: marker, atomically: true, encoding: .utf8)
    }

    // quit records a clean quit.
    func quit() {
        try? Data().write(to: quitNote)
    }
}
