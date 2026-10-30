import Foundation
import Testing

import MooringsCore

@testable import Moorings

// updateTag is the release the fakes offer, newer than updateCurrent.
let updateTag = "v9.0.0"
// updateCurrent is the running version the updater compares against.
let updateCurrent = ReleaseVersion("1.0.0")!
// updateZipName is the asset name of updateTag's zip.
let updateZipName = "moorings_\(updateTag)_macos_universal.zip"

// Counter counts calls from any thread.
final class Counter: @unchecked Sendable {
    // lock guards count.
    private let lock = NSLock()
    // value is the calls so far.
    private var value = 0

    // count is the calls so far.
    var count: Int { lock.withLock { value } }

    // add counts one call.
    func add() {
        lock.withLock { value += 1 }
    }
}

// FakeDownloader serves files by name and counts its calls.
struct FakeDownloader: Downloader {
    // files maps an asset name to its body.
    let files: [String: Data]
    // fail is thrown instead of serving, when set.
    var fail: (any Error & Sendable)?
    // calls counts downloads.
    let calls = Counter()

    // download writes the named body to file.
    func download(_ url: URL, to file: URL, limit: Int) async throws {
        calls.add()
        if let fail {
            throw fail
        }
        guard let data = files[url.lastPathComponent] else {
            throw DownloadError.status(404)
        }
        guard data.count <= limit else {
            throw DownloadError.tooLarge
        }
        try data.write(to: file)
    }
}

// FakeTrust returns a fixed verdict.
struct FakeTrust: Trust {
    // verdict is what every verify returns.
    let verdict: UpdateVerdict?

    // verify returns verdict.
    func verify(bundle: URL, version: String) -> UpdateVerdict? {
        verdict
    }
}

// UpdateRig is an updater on fakes in its own temporary folder.
@MainActor
struct UpdateRig {
    // dir is the rig's temporary folder.
    let dir: URL
    // zip is a real zip holding a Moorings.app.
    let zip: Data
    // sums is SHA256SUMS listing zip.
    let sums: Data
    // checks counts requests to GitHub.
    let checks = Counter()

    // init builds the zip and its checksums.
    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("updater-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("src/Moorings.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Info.plist"))
        let file = dir.appendingPathComponent(updateZipName)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--keepParent", dir.appendingPathComponent("src/Moorings.app").path, file.path]
        try task.run()
        task.waitUntilExit()
        zip = try Data(contentsOf: file)
        let hex = try #require(Updater.sha256(file))
        sums = Data("\(hex)  \(updateZipName)\n0000  other\n".utf8)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Applications/Moorings.app"), withIntermediateDirectories: true)
    }

    // release is GitHub's answer for updateTag, with or without its assets.
    func release(assets: Bool = true) -> Data {
        let base = "https://github.com/dcadolph/moorings/releases/download/\(updateTag)/"
        let list =
            assets
            ? #"[{"name":"\#(updateZipName)","browser_download_url":"\#(base)\#(updateZipName)"},"#
                + #"{"name":"SHA256SUMS","browser_download_url":"\#(base)SHA256SUMS"}]"#
            : "[]"
        let page = "https://github.com/dcadolph/moorings/releases/tag/\(updateTag)"
        return Data(
            #"{"tag_name":"\#(updateTag)","html_url":"\#(page)","draft":false,"prerelease":false,"assets":\#(list)}"#
                .utf8)
    }

    // updater builds an updater on the fakes.
    func updater(
        downloader: FakeDownloader, trust: UpdateVerdict? = nil, assets: Bool = true, bundle: URL? = nil
    ) -> Updater {
        let body = release(assets: assets)
        let checks = checks
        let client = HTTPClientFunc { _ in
            checks.add()
            return (body, 200)
        }
        return Updater(
            client: client, downloader: downloader, trust: FakeTrust(verdict: trust), current: updateCurrent,
            bundle: bundle ?? dir.appendingPathComponent("Applications/Moorings.app"),
            cache: dir.appendingPathComponent("cache"))
    }

    // downloader serves the rig's zip and checksums, or sums in their place.
    func downloader(sums other: Data? = nil) -> FakeDownloader {
        FakeDownloader(files: [updateZipName: zip, "SHA256SUMS": other ?? sums])
    }
}

// A refusal at each step of the trust chain lands in the state with its own word, and a clean
// release is staged.
@Test @MainActor func testUpdaterRefusals() async throws {
    let rig = try UpdateRig()
    let locked = URL(fileURLWithPath: "/System/Applications/Moorings.app")
    let wrong = Data("\(String(repeating: "ab", count: 32))  \(updateZipName)\n".utf8)
    let tests: [(trust: UpdateVerdict?, sums: Data?, assets: Bool, bundle: URL?, free: Int64, want: UpdateState)] = [
        // Test 0: Every check passes.
        (nil, nil, true, nil, .max, .verified(updateTag)),
        // Test 1: Signature.
        (.signature, nil, true, nil, .max, .refused(.signature, updateTag)),
        // Test 2: Requirement.
        (.requirement, nil, true, nil, .max, .refused(.requirement, updateTag)),
        // Test 3: Notarization.
        (.notarization, nil, true, nil, .max, .refused(.notarization, updateTag)),
        // Test 4: Info.plist.
        (.plist, nil, true, nil, .max, .refused(.plist, updateTag)),
        // Test 5: A checksum that differs.
        (nil, wrong, true, nil, .max, .refused(.checksum, updateTag)),
        // Test 6: No pinned assets.
        (nil, nil, false, nil, .max, .refused(.assets, updateTag)),
        // Test 7: A bundle in a folder this user cannot write.
        (nil, nil, true, locked, .max, .refused(.location, updateTag)),
        // Test 8: Too little free space.
        (nil, nil, true, nil, 0, .refused(.space, updateTag)),
    ]
    for (i, test) in tests.enumerated() {
        let u = rig.updater(
            downloader: rig.downloader(sums: test.sums), trust: test.trust, assets: test.assets, bundle: test.bundle)
        u.freeSpace = { _ in test.free }
        let found = try await u.check(automatic: true, install: true)
        #expect(found?.tag == updateTag, "test \(i)")
        #expect(u.state == test.want, "test \(i)")
        if case .verified = test.want {
            #expect(u.staged.map { FileManager.default.fileExists(atPath: $0.path) } == true, "test \(i)")
        } else {
            #expect(u.staged == nil, "test \(i)")
        }
    }
}

// A release older than the running version is refused at metadata.
@Test @MainActor func testUpdaterMetadata() async throws {
    let rig = try UpdateRig()
    let u = rig.updater(downloader: rig.downloader())
    let page = URL(string: "https://github.com/dcadolph/moorings/releases/tag/v0.9.0")!
    await u.fetch(ReleaseInfo(tag: "v0.9.0", page: page, zip: page, checksums: page))
    #expect(u.state == .refused(.metadata, "v0.9.0"))
}

// A refused tag is never fetched again in the same launch, and a skipped tag is never fetched.
@Test @MainActor func testUpdaterTriesOnce() async throws {
    let rig = try UpdateRig()
    let d = rig.downloader()
    let u = rig.updater(downloader: d, trust: .signature)
    try await u.check(automatic: true, install: true)
    let first = d.calls.count
    #expect(first == 2)
    try await u.check(automatic: true, install: true)
    #expect(d.calls.count == first)
    #expect(u.state == .refused(.signature, updateTag))

    let body = rig.release()
    let skipped = Updater(
        client: HTTPClientFunc { _ in (body, 200) }, downloader: d, trust: FakeTrust(verdict: nil),
        current: updateCurrent, bundle: rig.dir.appendingPathComponent("Applications/Moorings.app"),
        cache: rig.dir.appendingPathComponent("cache2"), skip: [updateTag])
    try await skipped.check(automatic: true, install: true)
    #expect(d.calls.count == first)
    #expect(skipped.state == .idle)
}

// With automatic checks off nothing is asked or downloaded, and with installs off the release is only
// offered: nothing is downloaded and the menu opens the release page.
@Test @MainActor func testUpdaterConsent() async throws {
    let rig = try UpdateRig()
    let d = rig.downloader()
    let u = rig.updater(downloader: d)
    let none = try await u.check(automatic: false, install: true)
    #expect(none == nil)
    #expect(rig.checks.count == 0 && d.calls.count == 0)

    let found = try await u.check(automatic: true, install: false)
    #expect(found?.tag == updateTag)
    #expect(rig.checks.count == 1 && d.calls.count == 0)
    #expect(u.state == .idle)
    let line = MenuBuilder.updateLine(u.state, release: u.release)
    #expect(line?.title == "Update available: \(updateTag)")

    let forced = try await rig.updater(downloader: d).check(automatic: false, install: false, forced: true)
    #expect(forced?.tag == updateTag)
    #expect(d.calls.count == 0)
}

// A download that fails in transit leaves the tag free for the next check.
@Test @MainActor func testUpdaterTransientFailure() async throws {
    let rig = try UpdateRig()
    var d = rig.downloader()
    d.fail = URLError(.notConnectedToInternet)
    let u = rig.updater(downloader: d)
    try await u.check(automatic: true, install: true)
    #expect(u.state == .idle)
    try await u.check(automatic: true, install: true)
    #expect(d.calls.count == 2)
}

// A staged update installs only at a quiet moment, and installNow skips the wait.
@Test @MainActor func testUpdaterQuietMoment() async throws {
    let rig = try UpdateRig()
    let u = rig.updater(downloader: rig.downloader())
    var installed: [String] = []
    var quiet = false
    u.quiet = { quiet }
    u.install = { staged, tag in
        installed.append(tag)
        #expect(staged.lastPathComponent == "Moorings.app")
    }
    try await u.check(automatic: true, install: true)
    #expect(u.state == .verified(updateTag))
    u.tick()
    #expect(installed.isEmpty)
    quiet = true
    u.tick()
    #expect(installed == [updateTag])
    #expect(u.state == .installing(updateTag))
    u.installNow()
    #expect(installed == [updateTag])
}

// swap puts the staged bundle in place and keeps the old one at previous.
@Test func testUpdaterSwap() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)")
    let files = FileManager.default
    let bundle = dir.appendingPathComponent("Applications/Moorings.app")
    let staged = dir.appendingPathComponent("cache/unpacked/Moorings.app")
    let previous = dir.appendingPathComponent("support/previous/Moorings.app")
    for (app, text) in [(bundle, "old"), (staged, "new")] {
        try files.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: app.appendingPathComponent("which"))
    }
    let backup = try Updater.swap(bundle: bundle, staged: staged, previous: previous)
    #expect(backup == previous)
    #expect(try String(contentsOf: bundle.appendingPathComponent("which"), encoding: .utf8) == "new")
    #expect(try String(contentsOf: previous.appendingPathComponent("which"), encoding: .utf8) == "old")
    #expect(!files.fileExists(atPath: dir.appendingPathComponent("Applications/Moorings.previous.app").path))
}

// HelperRig is a relaunch helper run on two fake bundles that are shell scripts.
struct HelperRig {
    // dir holds the fakes.
    let dir: URL
    // bundle is where the new build sits after the swap.
    var bundle: URL { dir.appendingPathComponent("Moorings.app") }
    // previous is the old build.
    var previous: URL { dir.appendingPathComponent("previous.app") }
    // failed is where a new build that never starts is parked.
    var failed: URL { dir.appendingPathComponent("failed.app") }
    // marker is the launch marker.
    var marker: URL { dir.appendingPathComponent("launched") }
    // oldRan is written when the old build runs.
    var oldRan: URL { dir.appendingPathComponent("old-ran") }

    // init writes the old build and a new build with the given body.
    init(newBody: String) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "echo old > '\(oldRan.path)'\n".write(to: previous, atomically: true, encoding: .utf8)
        try newBody.write(to: bundle, atomically: true, encoding: .utf8)
    }

    // run starts the helper after a process that has already exited, and waits up to 30 s for it.
    func run() throws {
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()
        var plan = Relaunch.Plan(bundle: bundle)
        plan.previous = previous
        plan.failed = failed
        plan.marker = marker
        plan.build = "42"
        plan.wait = 2
        plan.opener = "/bin/sh"
        plan.pid = gone.processIdentifier
        let task = try Relaunch.start(plan)
        let deadline = Date().addingTimeInterval(30)
        while task.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        #expect(!task.isRunning)
    }
}

// A new build that writes the marker keeps the swap, and one that exits or hangs without it is
// swapped back, a hung one is stopped, and the old build runs again.
@Test func testRelaunchHelper() throws {
    let started = try HelperRig(newBody: "echo 42 > \"$(dirname \"$0\")/launched\"\n")
    try started.run()
    #expect(try String(contentsOf: started.bundle, encoding: .utf8).contains("echo 42"))
    #expect(FileManager.default.fileExists(atPath: started.previous.path))
    #expect(!FileManager.default.fileExists(atPath: started.oldRan.path))

    let crashed = try HelperRig(newBody: "exit 1\n")
    try crashed.run()
    #expect(try String(contentsOf: crashed.bundle, encoding: .utf8).contains("echo old"))
    #expect(try String(contentsOf: crashed.failed, encoding: .utf8) == "exit 1\n")
    #expect(FileManager.default.fileExists(atPath: crashed.oldRan.path))

    let hung = try HelperRig(newBody: "/bin/sleep 60\n")
    try hung.run()
    #expect(try String(contentsOf: hung.bundle, encoding: .utf8).contains("echo old"))
    #expect(FileManager.default.fileExists(atPath: hung.oldRan.path))
    let left = Process()
    left.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    left.arguments = ["-f", "--", hung.dir.path]
    try left.run()
    left.waitUntilExit()
    #expect(left.terminationStatus == 1, "a hung build is still running")
}

// The marker tells a launch whether the last run of its build ended without Quit, and finish clears
// the quit note so the next crash shows.
@Test func testLaunchMarker() throws {
    let tests: [(last: String?, quit: Bool, build: String, want: Bool)] = [
        // Test 0: First launch ever.
        (nil, false, "36", false),
        // Test 1: The last run of this build quit.
        ("36", true, "36", false),
        // Test 2: The last run of this build ended without Quit.
        ("36", false, "36", true),
        // Test 3: A new build after an older one that ended without Quit.
        ("35", false, "36", false),
    ]
    for (i, test) in tests.enumerated() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = LaunchMarker(folder: dir)
        if let last = test.last {
            m.finish(build: last)
        }
        if test.quit {
            m.quit()
        }
        #expect(m.begin(build: test.build, pid: 7) == test.want, "test \(i)")
        #expect(try String(contentsOf: m.starting, encoding: .utf8) == "\(test.build) 7\n", "test \(i)")
        m.finish(build: test.build)
        #expect(!FileManager.default.fileExists(atPath: m.quitNote.path), "test \(i)")
        #expect(try String(contentsOf: m.marker, encoding: .utf8) == "\(test.build)\n", "test \(i)")
    }
}
