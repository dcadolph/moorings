import Foundation

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

    // init creates a release from its tag and page.
    public init(tag: String, page: URL) {
        self.tag = tag
        self.page = page
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
        return ReleaseInfo(tag: release.tagName, page: page)
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

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
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
    public static func isDue(lastChecked: Date?, launched: Date, now: Date,
                             fresh: TimeInterval = everySeconds) -> Bool {
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
