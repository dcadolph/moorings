import Foundation
import Testing

@testable import MooringsCore

// BackupDecodeCase is one backup file reading expectation.
struct BackupDecodeCase: Sendable, CustomTestStringConvertible {
    // name labels the case in test output.
    let name: String
    // json is the file content.
    let json: String
    // wantPaused is the expected paused value when the file loads.
    let wantPaused: Bool?
    // want is the expected error, or nil when the file loads.
    let want: BackupError?

    // testDescription labels the case in test output.
    var testDescription: String { name }
}

// backupDecodeCases covers a current file, a sparse file, and every refusal.
let backupDecodeCases: [BackupDecodeCase] = [
    // Sheepdog: current file loads.
    BackupDecodeCase(
        name: "current",
        json: #"{"app":"moorings","version":1,"exported":"2026-10-23T18:00:00Z","settings":{"paused":true}}"#,
        wantPaused: true, want: nil
    ),
    // Sheepdog: older version with missing keys loads with defaults.
    BackupDecodeCase(
        name: "older sparse",
        json: #"{"app":"moorings","version":0,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantPaused: false, want: nil
    ),
    // Sheepdog: another app's file is refused.
    BackupDecodeCase(
        name: "other app",
        json: #"{"app":"sheepdog","version":1,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantPaused: nil, want: .notMoorings("sheepdog")
    ),
    // Sheepdog: a newer format is refused.
    BackupDecodeCase(
        name: "newer version",
        json: #"{"app":"moorings","version":2,"exported":"2026-10-23T18:00:00Z","settings":{}}"#,
        wantPaused: nil, want: .newerVersion(2)
    ),
    // Sheepdog: junk is refused.
    BackupDecodeCase(name: "junk", json: "not json", wantPaused: nil, want: .unreadable),
    // Sheepdog: bare settings without the header are refused.
    BackupDecodeCase(name: "no header", json: #"{"paused":true}"#, wantPaused: nil, want: .unreadable),
    // Sheepdog: a header with settings that are not an object is refused.
    BackupDecodeCase(
        name: "broken settings",
        json: #"{"app":"moorings","version":1,"exported":"2026-10-23T18:00:00Z","settings":5}"#,
        wantPaused: nil, want: .unreadable
    ),
    // Sheepdog: a file naming only another app, as the negative control feeds it, is refused.
    BackupDecodeCase(
        name: "app only",
        json: #"{"app":"sheepdog"}"#,
        wantPaused: nil, want: .unreadable
    ),
]

// testSettingsBackupDecode checks loading and refusing backup files.
@Test(arguments: backupDecodeCases)
func testSettingsBackupDecode(test: BackupDecodeCase) {
    do {
        let got = try SettingsBackup.decode(Data(test.json.utf8))
        #expect(test.want == nil)
        #expect(got.paused == test.wantPaused)
    } catch let error as BackupError {
        #expect(error == test.want)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}

// testSettingsBackupRefusesOtherApp checks the refusal comes from the app name check, since the
// rest of the file is valid.
@Test func testSettingsBackupRefusesOtherApp() {
    let json = #"{"app":"sheepdog","version":1,"exported":"2026-10-23T18:00:00Z","settings":{}}"#
    #expect(throws: BackupError.notMoorings("sheepdog")) {
        try SettingsBackup.decode(Data(json.utf8))
    }
}

// testSettingsBackupRoundTrip checks that choices survive export and import, and that the file
// names the app and version.
@Test func testSettingsBackupRoundTrip() throws {
    let choices = Choices(slots: [.leftTop: "com.apple.Safari", .rightBottom: "com.apple.Notes"], paused: true)
    let data = try SettingsBackup.encode(choices, exported: Date(timeIntervalSince1970: 1_792_000_000))
    #expect(try SettingsBackup.decode(data) == choices)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""app" : "moorings""#))
    #expect(text.contains(#""version" : 1"#))
}
