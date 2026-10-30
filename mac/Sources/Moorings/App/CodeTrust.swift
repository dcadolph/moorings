import Foundation
import Security

import MooringsCore

// CodeTrust decides whether a downloaded Moorings bundle may replace the running app. Each check
// refuses on any mismatch and names the step that refused.
enum CodeTrust {
    // bundleID is the identifier every Moorings release carries.
    static let bundleID = "com.dcadolph.moorings"
    // requirement is the designated requirement of a Moorings release: Apple's Developer ID chain
    // with the leaf issued to the personal team, so a build signed by any other team, ad hoc or
    // with a development certificate fails it.
    static let requirement =
        "identifier \"\(bundleID)\" and anchor apple generic"
        + " and certificate 1[field.1.2.840.113635.100.6.2.6]"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13]"
        + " and certificate leaf[subject.OU] = U7L4P2YHWJ"
    // notarizedSource is the spctl source line a notarized Developer ID bundle prints.
    static let notarizedSource = "source=Notarized Developer ID"
    // assessTimeout bounds the spctl run.
    static let assessTimeout: TimeInterval = 20

    // verify runs the signature, designated requirement, notarization and Info.plist checks on the
    // bundle in that order and returns the first refusal, or nil when every check passes. running
    // is the running app's designated requirement, and current is its version.
    static func verify(bundle: URL, version: String, current: ReleaseVersion, running: String?) -> UpdateVerdict? {
        guard signed(bundle) else {
            return .signature
        }
        guard let running, let candidate = designatedRequirement(of: bundle), candidate == running else {
            return .requirement
        }
        guard notarized(assess(bundle)) else {
            return .notarization
        }
        guard plistMatches(bundle, version: version, current: current) else {
            return .plist
        }
        return nil
    }

    // signed reports whether every architecture and nested item of the bundle carries a valid
    // signature that satisfies requirement.
    static func signed(_ bundle: URL, requirement text: String = requirement) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return false
        }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req else {
            return false
        }
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidityWithErrors(code, flags, req, nil) == errSecSuccess
    }

    // designatedRequirement returns the designated requirement of the bundle as text, or nil when
    // it has none.
    static func designatedRequirement(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return nil
        }
        return text(of: code)
    }

    // runningRequirement returns the running app's designated requirement as text, or nil when the
    // app is unsigned.
    static func runningRequirement() -> String? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else {
            return nil
        }
        var code: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &code) == errSecSuccess, let code else {
            return nil
        }
        return text(of: code)
    }

    // text renders the designated requirement of the static code.
    private static func text(of code: SecStaticCode) -> String? {
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess, let req else {
            return nil
        }
        var out: CFString?
        guard SecRequirementCopyString(req, [], &out) == errSecSuccess, let out else {
            return nil
        }
        return out as String
    }

    // assess runs spctl's execute assessment on the bundle and returns what it printed, or an
    // empty string when it could not run or ran past assessTimeout. The output goes to a file rather
    // than a pipe, so the wait is bounded by the timeout and never by spctl closing its output.
    static func assess(_ bundle: URL) -> String {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("spctl-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: out.path, contents: nil),
            let handle = try? FileHandle(forWritingTo: out)
        else {
            return ""
        }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: out)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        task.arguments = ["--assess", "--type", "execute", "--verbose=4", bundle.path]
        task.standardOutput = handle
        task.standardError = handle
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        do {
            try task.run()
        } catch {
            return ""
        }
        guard done.wait(timeout: .now() + assessTimeout) == .success else {
            task.terminate()
            return ""
        }
        guard task.terminationStatus == 0, let data = try? Data(contentsOf: out) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    // notarized reports whether spctl output accepts the bundle as notarized Developer ID code.
    static func notarized(_ output: String) -> Bool {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains { $0.hasSuffix(": accepted") } && lines.contains(notarizedSource)
    }

    // plistMatches reports whether the bundle's Info.plist names Moorings at the expected version,
    // that version is newer than current, and the bundle runs on os.
    static func plistMatches(
        _ bundle: URL, version: String, current: ReleaseVersion,
        os: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Bool {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["CFBundleIdentifier"] as? String == bundleID,
            let short = plist["CFBundleShortVersionString"] as? String, short == version,
            let got = ReleaseVersion(short)
        else {
            return false
        }
        return got > current && runs(minimum: plist["LSMinimumSystemVersion"] as? String, on: os)
    }

    // runs reports whether a bundle that needs minimum runs on os. A bundle that names no minimum
    // runs anywhere, and one whose minimum cannot be read runs nowhere.
    static func runs(minimum: String?, on os: OperatingSystemVersion) -> Bool {
        guard let minimum else {
            return true
        }
        let parts = minimum.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(nil) else {
            return false
        }
        let need = parts.compactMap { $0 } + Array(repeating: 0, count: 3 - parts.count)
        let have = [os.majorVersion, os.minorVersion, os.patchVersion]
        return !have.lexicographicallyPrecedes(need)
    }
}
