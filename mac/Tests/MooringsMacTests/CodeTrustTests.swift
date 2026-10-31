import Foundation
import Testing

import MooringsCore

@testable import Moorings

// releaseApp is the installed Moorings release the trust tests measure against.
let releaseApp = URL(fileURLWithPath: "/Applications/Moorings.app")

// oldVersion is a running version every release is newer than.
let oldVersion = ReleaseVersion("1.0.0")!

// releaseVersion reads the short version of the bundle, or nil when it has none.
func releaseVersion(_ bundle: URL) -> String? {
    NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"]
        as? String
}

// hasNotarizedRelease reports whether the installed release is a notarized Moorings.
func hasNotarizedRelease() -> Bool {
    FileManager.default.fileExists(atPath: releaseApp.path) && CodeTrust.notarized(CodeTrust.assess(releaseApp))
}

// thirdPartyApps lists the installed Developer ID apps from other teams.
let thirdPartyApps = ["/Applications/Rectangle.app", "/Applications/Loop.app"]

// hasThirdPartyDeveloperIDApp reports whether any app for the wrong-team case is installed.
func hasThirdPartyDeveloperIDApp() -> Bool {
    thirdPartyApps.contains { FileManager.default.fileExists(atPath: $0) }
}

// releaseCopy copies the installed release into a fresh temporary folder.
func releaseCopy(_ release: URL) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codetrust-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let copy = dir.appendingPathComponent("Moorings.app")
    try FileManager.default.copyItem(at: release, to: copy)
    return copy
}

// run runs a tool to completion and returns its exit status.
@discardableResult
func run(_ tool: String, _ args: String...) throws -> Int32 {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: tool)
    task.arguments = args
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    return task.terminationStatus
}

// The installed notarized release passes every check against its own designated requirement.
@Test(.enabled(if: hasNotarizedRelease(), "no notarized Moorings release in /Applications"))
func testCodeTrustRelease() throws {
    let release = releaseApp
    let version = try #require(releaseVersion(release))
    let running = CodeTrust.designatedRequirement(of: release)
    #expect(CodeTrust.verify(bundle: release, version: version, current: oldVersion, running: running) == nil)
}

// A release fails at plist when its version is not the tag's or not newer than the running one,
// and at requirement when the running app's designated requirement differs or is missing.
@Test(.enabled(if: hasNotarizedRelease(), "no notarized Moorings release in /Applications"))
func testCodeTrustPlistAndRequirement() throws {
    let release = releaseApp
    let version = try #require(releaseVersion(release))
    let running = CodeTrust.designatedRequirement(of: release)
    let tests: [(version: String, current: ReleaseVersion, running: String?, want: UpdateVerdict)] = [
        // Test 0: The tag names another version.
        ("99.0.0", oldVersion, running, .plist),
        // Test 1: The release is the running version.
        (version, try #require(ReleaseVersion(version)), running, .plist),
        // Test 2: The running app was signed another way.
        (version, oldVersion, "identifier \"com.dcadolph.moorings\" and anchor apple", .requirement),
        // Test 3: The running app is unsigned.
        (version, oldVersion, nil, .requirement),
    ]
    for (testNum, test) in tests.enumerated() {
        let got = CodeTrust.verify(bundle: release, version: test.version, current: test.current, running: test.running)
        #expect(got == test.want, "test \(testNum)")
    }
}

// Bundles signed by another team, ad hoc, or changed after signing fail at signature.
@Test(
    .enabled(if: hasNotarizedRelease(), "no notarized Moorings release in /Applications"),
    .enabled(if: hasThirdPartyDeveloperIDApp(), "no third-party Developer ID app for the wrong-team case")
)
func testCodeTrustRefusesSignature() throws {
    let release = releaseApp
    let running = CodeTrust.designatedRequirement(of: release)
    var bundles: [(name: String, url: URL)] = []
    for other in thirdPartyApps where FileManager.default.fileExists(atPath: other) {
        bundles.append((other, URL(fileURLWithPath: other)))
    }

    let adhoc = try releaseCopy(release)
    #expect(try run("/usr/bin/codesign", "--force", "--deep", "--sign", "-", adhoc.path) == 0)
    bundles.append(("ad hoc", adhoc))

    let icon = try releaseCopy(release)
    let iconURL = icon.appendingPathComponent("Contents/Resources/AppIcon.icns")
    var bytes = try Data(contentsOf: iconURL)
    bytes[bytes.count / 2] ^= 0xFF
    try bytes.write(to: iconURL)
    bundles.append(("icon byte", icon))

    let renamed = try releaseCopy(release)
    let plist = renamed.appendingPathComponent("Contents/Info.plist").path
    #expect(try run("/usr/bin/plutil", "-replace", "CFBundleIdentifier", "-string", "com.example.moorings", plist) == 0)
    bundles.append(("identifier", renamed))

    for bundle in bundles {
        let version = releaseVersion(bundle.url) ?? "1.0.1"
        let got = CodeTrust.verify(bundle: bundle.url, version: version, current: oldVersion, running: running)
        #expect(got == .signature, "\(bundle.name)")
    }
}

// A validly signed bundle named by MOORINGS_UNNOTARIZED_APP, a local Developer ID build that was
// never notarized, fails at notarization.
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["MOORINGS_UNNOTARIZED_APP"] != nil,
        "MOORINGS_UNNOTARIZED_APP is not set"))
func testCodeTrustRefusesUnnotarized() throws {
    let path = try #require(ProcessInfo.processInfo.environment["MOORINGS_UNNOTARIZED_APP"])
    let bundle = URL(fileURLWithPath: path)
    let version = try #require(releaseVersion(bundle))
    let running = CodeTrust.designatedRequirement(of: bundle)
    #expect(CodeTrust.verify(bundle: bundle, version: version, current: oldVersion, running: running) == .notarization)
}

// Only an accepted assessment with the notarized Developer ID source counts as notarized.
@Test func testCodeTrustNotarizedOutput() {
    let tests: [(output: String, want: Bool)] = [
        // Test 0: A notarized release.
        ("/Applications/Moorings.app: accepted\nsource=Notarized Developer ID\n", true),
        // Test 1: Signed but not notarized.
        ("/tmp/Moorings.app: accepted\nsource=Developer ID\n", false),
        // Test 2: Rejected.
        ("/tmp/Moorings.app: rejected\nsource=Unnotarized Developer ID\n", false),
        // Test 3: Rejected with a notarized source line.
        ("/tmp/Moorings.app: rejected\nsource=Notarized Developer ID\n", false),
        // Test 4: Assessments turned off print no source.
        ("/tmp/Moorings.app: accepted\n", false),
        // Test 5: spctl did not run.
        ("", false),
    ]
    for (testNum, test) in tests.enumerated() {
        #expect(CodeTrust.notarized(test.output) == test.want, "test \(testNum)")
    }
}

// A release that needs a newer macOS than the Mac runs is refused, and one that names no minimum
// or an older one is accepted.
@Test func testCodeTrustMinimumSystem() throws {
    let os = OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 1)
    let tests: [(minimum: String?, want: Bool)] = [
        (nil, true), ("14.0", true), ("15", true), ("15.6.1", true), ("15.6.2", false), ("15.7", false),
        ("26.0", false), ("", false), ("15.x", false), ("1.2.3.4", false),
    ]
    for (i, test) in tests.enumerated() {
        #expect(CodeTrust.runs(minimum: test.minimum, on: os) == test.want, "test \(i)")
    }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("minos-\(UUID().uuidString)")
    let contents = dir.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let plist: [String: Any] = [
        "CFBundleIdentifier": CodeTrust.bundleID, "CFBundleShortVersionString": "1.16.0",
        "LSMinimumSystemVersion": "26.0",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    let current = try #require(ReleaseVersion("1.15.1"))
    #expect(!CodeTrust.plistMatches(dir, version: "1.16.0", current: current, os: os))
    #expect(
        CodeTrust.plistMatches(
            dir, version: "1.16.0", current: current,
            os: OperatingSystemVersion(
                majorVersion: 26, minorVersion: 0, patchVersion: 0)))
}
