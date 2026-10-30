import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// UpdateError names why an update check failed.
public enum UpdateError: Error, Equatable, Sendable {
    // server reports a status other than 200.
    case server(status: Int)
    // decode reports a body that is not a release.
    case decode
}

// ReleaseVersion is a release number such as 1.2.3.
public struct ReleaseVersion: Sendable, Comparable, Equatable {
    // Major is the first number.
    public let major: Int
    // Minor is the second number.
    public let minor: Int
    // Patch is the third number.
    public let patch: Int

    // init parses "1.2.3" or "v1.2.3", and returns nil for anything else, prereleases included.
    public init?(_ text: String) {
        let body = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        let numbers = parts.compactMap { part in
            part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil
        }
        guard numbers.count == 3 else {
            return nil
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    // < orders versions by major, then minor, then patch.
    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// ReleaseInfo is a published release worth telling the user about.
public struct ReleaseInfo: Sendable, Equatable {
    // Tag is the release tag, e.g. v1.3.0.
    public let tag: String
    // Page is the release page the user is sent to.
    public let page: URL
    // Zip is the universal macOS zip asset, or nil when the release lacks a trusted one.
    public let zip: URL?
    // Checksums is the SHA256SUMS asset, or nil when the release lacks a trusted one.
    public let checksums: URL?

    // init creates a release from its tag, page and optional assets.
    public init(tag: String, page: URL, zip: URL? = nil, checksums: URL? = nil) {
        self.tag = tag
        self.page = page
        self.zip = zip
        self.checksums = checksums
    }

    // assetURL returns the asset of the given name when it sits at the pinned download path for
    // the tag on github.com over https, and nil otherwise.
    static func assetURL(tag: String, name: String, in assets: [Asset]) -> URL? {
        guard !tag.isEmpty, !tag.hasPrefix("."),
            tag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else {
            return nil
        }
        let prefix = "/dcadolph/moorings/releases/download/\(tag)/"
        for asset in assets where asset.name == name {
            guard let url = URL(string: asset.url), url.scheme == "https", url.host == "github.com",
                url.port == nil, url.user == nil, url.password == nil,
                url.path == prefix + name
            else {
                continue
            }
            return url
        }
        return nil
    }

    // Asset is one entry of a release's assets list.
    struct Asset: Decodable, Equatable {
        // Name is the asset file name.
        let name: String
        // URL is the browser download URL.
        let url: String

        enum CodingKeys: String, CodingKey {
            case name
            case url = "browser_download_url"
        }
    }
}

// UpdateVerdict names the step of the update trust chain that refused, so every refusal maps to
// one word.
public enum UpdateVerdict: String, Sendable, Equatable, CaseIterable {
    // metadata is a release record that is missing, malformed or not newer.
    case metadata
    // assets is a release without the pinned zip or checksum asset.
    case assets
    // checksum is a download whose hash is absent from or differs from SHA256SUMS.
    case checksum
    // signature is a bundle whose code signature is invalid.
    case signature
    // requirement is a bundle that fails the signing requirement or the designated requirement match.
    case requirement
    // notarization is a bundle Gatekeeper does not accept as notarized.
    case notarization
    // plist is a bundle whose Info.plist differs from what is expected.
    case plist
    // location is an install location that cannot be replaced.
    case location
    // space is too little free disk space to stage the update.
    case space
}

// Checksums reads and checks `shasum -a 256` output.
public enum Checksums {
    // parse maps file names to lowercase hex digests. Lines are "<hex>  <name>" or "<hex> *<name>".
    // Lines that do not fit are skipped, and a later line for the same name replaces an earlier one.
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let hex = line.prefix { $0.isASCII && $0.isHexDigit }
            guard hex.count == 64 else {
                continue
            }
            var rest = line.dropFirst(hex.count)
            guard rest.first == " " else {
                continue
            }
            rest = rest.dropFirst()
            guard rest.first == " " || rest.first == "*" else {
                continue
            }
            let name = String(rest.dropFirst())
            guard !name.isEmpty else {
                continue
            }
            result[name] = hex.lowercased()
        }
        return result
    }

    // matches reports whether the digest equals the one listed for the exact name, ignoring hex case.
    public static func matches(_ hex: String, name: String, in sums: [String: String]) -> Bool {
        guard let want = sums[name] else {
            return false
        }
        return want == hex.lowercased()
    }
}

// UpdateChecker asks GitHub whether a newer release exists.
public struct UpdateChecker: Sendable {
    // api is the endpoint that names the latest release.
    public static let api = URL(string: "https://api.github.com/repos/dcadolph/moorings/releases/latest")!

    // client sends the request.
    let client: any HTTPClient
    // current is the running version.
    let current: ReleaseVersion

    // init creates a checker for the running version.
    public init(client: any HTTPClient, current: ReleaseVersion) {
        self.client = client
        self.current = current
    }

    // check returns the latest release when it is newer than the running version, and nil otherwise.
    // Drafts, prereleases, tags that do not parse and pages that are not https on github.com are never newer.
    public func check() async throws -> ReleaseInfo? {
        var request = URLRequest(url: Self.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, status) = try await client.send(request)
        guard status == 200 else {
            throw UpdateError.server(status: status)
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            throw UpdateError.decode
        }
        guard !(release.draft ?? false), !(release.prerelease ?? false),
            let version = ReleaseVersion(release.tagName), version > current,
            let page = URL(string: release.htmlURL), page.scheme == "https", page.host == "github.com"
        else {
            return nil
        }
        let assets = release.assets ?? []
        return ReleaseInfo(
            tag: release.tagName, page: page,
            zip: ReleaseInfo.assetURL(
                tag: release.tagName, name: "moorings_\(release.tagName)_macos_universal.zip", in: assets),
            checksums: ReleaseInfo.assetURL(tag: release.tagName, name: "SHA256SUMS", in: assets))
    }

    // Release is the part of GitHub's release response the check reads.
    private struct Release: Decodable {
        // TagName is the release tag.
        let tagName: String
        // HTMLURL is the release page.
        let htmlURL: String
        // Draft reports an unpublished release.
        let draft: Bool?
        // Prerelease reports a release marked as a prerelease.
        let prerelease: Bool?
        // Assets lists the files attached to the release.
        let assets: [ReleaseInfo.Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }
}

// UpdateSchedule decides when the next check is due.
public enum UpdateSchedule {
    // everySeconds is how long one check stays fresh for the timer.
    public static let everySeconds: TimeInterval = 6 * 60 * 60
    // menuSeconds is how long one check stays fresh when the menu opens.
    public static let menuSeconds: TimeInterval = 60 * 60
    // firstSeconds is how long after launch the first check waits, so it never slows a login.
    public static let firstSeconds: TimeInterval = 60

    // isDue reports whether a check older than fresh seconds should run now. A clock set behind the
    // last check counts as due.
    public static func isDue(
        lastChecked: Date?, launched: Date, now: Date,
        fresh: TimeInterval = everySeconds
    ) -> Bool {
        guard now.timeIntervalSince(launched) >= firstSeconds else {
            return false
        }
        guard let lastChecked else {
            return true
        }
        let age = now.timeIntervalSince(lastChecked)
        return age >= fresh || age < 0
    }
}
