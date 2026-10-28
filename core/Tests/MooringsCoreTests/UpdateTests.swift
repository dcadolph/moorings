import Foundation
import Testing

@testable import MooringsCore

// VersionCase is one text and the version it should parse to.
struct VersionCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Text is the version text.
    let text: String
    // Want is the parsed numbers, or nil when the text is not a release version.
    let want: [Int]?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// versionCases cover accepted and refused spellings.
let versionCases: [VersionCase] = [
    // Sheepdog: Plain.
    VersionCase(name: "plain", text: "1.2.3", want: [1, 2, 3]),
    // Sheepdog: Prefixed.
    VersionCase(name: "v prefix", text: "v1.2.3", want: [1, 2, 3]),
    // Sheepdog: Two parts.
    VersionCase(name: "two parts", text: "1.2", want: nil),
    // Sheepdog: Four parts.
    VersionCase(name: "four parts", text: "1.2.3.4", want: nil),
    // Sheepdog: Prerelease.
    VersionCase(name: "prerelease", text: "v1.2.3-rc1", want: nil),
    // Sheepdog: Words.
    VersionCase(name: "garbage", text: "latest", want: nil),
    // Sheepdog: Empty.
    VersionCase(name: "empty", text: "", want: nil),
    // Sheepdog: Empty part.
    VersionCase(name: "empty part", text: "1..3", want: nil),
    // Sheepdog: Sign.
    VersionCase(name: "sign", text: "1.+2.3", want: nil),
    // Sheepdog: Arabic-Indic digit.
    VersionCase(name: "non-ASCII digit", text: "1.٢.3", want: nil),
    // Sheepdog: Double prefix.
    VersionCase(name: "double v", text: "vv1.2.3", want: nil),
]

// Lua case 0
// testReleaseVersionParse checks which spellings parse.
@Test(arguments: versionCases)
func testReleaseVersionParse(test: VersionCase) {
    let got = ReleaseVersion(test.text).map { [$0.major, $0.minor, $0.patch] }
    #expect(got == test.want)
}

// Lua case 1
// testReleaseVersionOrder checks ordering, including numeric rather than text order.
@Test func testReleaseVersionOrder() throws {
    let v190 = try #require(ReleaseVersion("1.9.0"))
    let v1100 = try #require(ReleaseVersion("1.10.0"))
    let v120 = try #require(ReleaseVersion("1.2.0"))
    let v121 = try #require(ReleaseVersion("1.2.1"))
    #expect(v1100 > v190)
    #expect(v121 > v120)
    #expect(!(v120 > v120))
    #expect(!(v120 > v121))
}

// UpdateCase is one fake GitHub response and the outcome the checker should give.
struct UpdateCase: Sendable, CustomTestStringConvertible {
    // Name labels the case in test output.
    let name: String
    // Status is the HTTP status returned.
    let status: Int
    // Body is the response body.
    let body: String
    // WantTag is the tag expected back, or nil when no update is reported.
    let wantTag: String?
    // Want is the error expected, or nil for none.
    let want: UpdateError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// release builds a GitHub release body.
func release(tag: String, url: String = "https://github.com/dcadolph/moorings/releases/tag/v9", extra: String = "")
    -> String
{
    "{\"tag_name\":\"\(tag)\",\"html_url\":\"\(url)\"\(extra)}"
}

// updateCases run the checker against the running version 1.2.0.
let updateCases: [UpdateCase] = [
    // Sheepdog: A newer release is reported.
    UpdateCase(
        name: "newer", status: 200, body: release(tag: "v1.3.0"), wantTag: "v1.3.0", want: nil
    ),
    // Sheepdog: The same release is not.
    UpdateCase(
        name: "same", status: 200, body: release(tag: "v1.2.0"), wantTag: nil, want: nil
    ),
    // Sheepdog: An older release is not.
    UpdateCase(
        name: "older", status: 200, body: release(tag: "v1.1.1"), wantTag: nil, want: nil
    ),
    // Sheepdog: A prerelease is ignored.
    UpdateCase(
        name: "prerelease flag", status: 200, body: release(tag: "v1.3.0", extra: ",\"prerelease\":true"),
        wantTag: nil, want: nil
    ),
    // Sheepdog: A draft is ignored.
    UpdateCase(
        name: "draft", status: 200, body: release(tag: "v1.3.0", extra: ",\"draft\":true"), wantTag: nil, want: nil
    ),
    // Sheepdog: A tag that does not parse is ignored.
    UpdateCase(
        name: "odd tag", status: 200, body: release(tag: "nightly"), wantTag: nil, want: nil
    ),
    // Sheepdog: A page off github.com is ignored.
    UpdateCase(
        name: "foreign page", status: 200, body: release(tag: "v1.3.0", url: "https://example.com/x"),
        wantTag: nil, want: nil
    ),
    // Sheepdog: A plain http page is ignored.
    UpdateCase(
        name: "http page", status: 200, body: release(tag: "v1.3.0", url: "http://github.com/x"),
        wantTag: nil, want: nil
    ),
    // Sheepdog: A missing release is a server error.
    UpdateCase(
        name: "not found", status: 404, body: "{}", wantTag: nil, want: .server(status: 404)
    ),
    // Sheepdog: A rate limit is a server error.
    UpdateCase(
        name: "rate limited", status: 403, body: "{}", wantTag: nil, want: .server(status: 403)
    ),
    // Sheepdog: Too many requests is a server error.
    UpdateCase(
        name: "too many", status: 429, body: "{}", wantTag: nil, want: .server(status: 429)
    ),
    // Sheepdog: A body that is not a release is a decode error.
    UpdateCase(
        name: "malformed", status: 200, body: "not json", wantTag: nil, want: .decode
    ),
    // Sheepdog: A release with no tag is a decode error.
    UpdateCase(
        name: "no tag", status: 200, body: "{\"html_url\":\"https://github.com/x\"}", wantTag: nil, want: .decode
    ),
]

// testUpdateChecker checks the outcome for each fake response.
@Test(arguments: updateCases)
func testUpdateChecker(test: UpdateCase) async throws {
    let client = HTTPClientFunc { _ in (Data(test.body.utf8), test.status) }
    let checker = UpdateChecker(client: client, current: try #require(ReleaseVersion("1.2.0")))
    if let want = test.want {
        await #expect(throws: want) { try await checker.check() }
        return
    }
    let got = try await checker.check()
    #expect(got?.tag == test.wantTag)
}

// testUpdateCheckerTransportError checks that a thrown transport error passes through.
@Test func testUpdateCheckerTransportError() async throws {
    struct Down: Error {}
    let client = HTTPClientFunc { _ in throw Down() }
    let checker = UpdateChecker(client: client, current: try #require(ReleaseVersion("1.2.0")))
    await #expect(throws: Down.self) { try await checker.check() }
}

// testUpdateSchedule checks the launch delay, the six-hour freshness and a clock set backward.
@Test func testUpdateSchedule() {
    let launched = updateStamp("2026-10-23 09:00")
    let last = updateStamp("2026-10-23 09:01")
    #expect(!UpdateSchedule.isDue(lastChecked: nil, launched: launched, now: updateStamp("2026-10-23 09:00")))
    #expect(UpdateSchedule.isDue(lastChecked: nil, launched: launched, now: updateStamp("2026-10-23 09:01")))
    #expect(!UpdateSchedule.isDue(lastChecked: last, launched: launched, now: updateStamp("2026-10-23 15:00")))
    #expect(UpdateSchedule.isDue(lastChecked: last, launched: launched, now: updateStamp("2026-10-23 15:01")))
    #expect(UpdateSchedule.isDue(lastChecked: updateStamp("2026-10-25 09:00"), launched: launched, now: last))
}

// testUpdateScheduleMenu checks that a menu open counts a check older than an hour as due.
@Test func testUpdateScheduleMenu() {
    let launched = updateStamp("2026-10-23 09:00")
    let last = updateStamp("2026-10-23 09:01")
    let fresh = UpdateSchedule.menuSeconds
    let hour = updateStamp("2026-10-23 10:00")
    let past = updateStamp("2026-10-23 10:01")
    #expect(!UpdateSchedule.isDue(lastChecked: last, launched: launched, now: hour, fresh: fresh))
    #expect(UpdateSchedule.isDue(lastChecked: last, launched: launched, now: past, fresh: fresh))
    #expect(!UpdateSchedule.isDue(lastChecked: last, launched: launched, now: past))
}

// updateStamp parses a UTC "yyyy-MM-dd HH:mm" string.
func updateStamp(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}
