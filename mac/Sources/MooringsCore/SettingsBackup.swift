import Foundation

// BackupError names why a settings file was refused.
public enum BackupError: Error, Equatable, Sendable {
    // unreadable reports a file that is not a moorings settings file.
    case unreadable
    // notMoorings reports a file written by another app, carrying that app's name.
    case notMoorings(String)
    // newerVersion reports a file from a newer format, carrying its version.
    case newerVersion(Int)
}

// SettingsBackup is the file a user exports to keep their settings and imports to restore them.
public struct SettingsBackup: Sendable, Codable, Equatable {
    // app names the app that wrote the file.
    public var app: String
    // version is the file format version.
    public var version: Int
    // exported is when the file was written.
    public var exported: Date
    // settings is the saved configuration.
    public var settings: Choices

    // appName is the app value this build writes and accepts.
    public static let appName = "moorings"
    // currentVersion is the newest format this build reads, and the one it writes.
    public static let currentVersion = 1
    // fileName is the suggested name for an exported file.
    public static let fileName = "Moorings Settings.json"

    // encode writes settings as pretty JSON with sorted keys, so the file diffs cleanly.
    public static func encode(_ settings: Choices, exported: Date) throws -> Data {
        let backup = SettingsBackup(app: appName, version: currentVersion, exported: exported, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // decode reads a backup file and returns its settings, refusing other apps and newer formats.
    // Workspaces come back untied, since the file may come from another set of displays.
    public static func decode(_ data: Data) throws -> Choices {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw BackupError.unreadable
        }
        guard header.app == appName else {
            throw BackupError.notMoorings(header.app)
        }
        guard header.version <= currentVersion else {
            throw BackupError.newerVersion(header.version)
        }
        guard let backup = try? decoder.decode(SettingsBackup.self, from: data) else {
            throw BackupError.unreadable
        }
        var settings = backup.settings
        for name in settings.workspaces.keys {
            settings.workspaces[name]?.setup = nil
        }
        return settings
    }

    // Header is the part of the file read before trusting the rest.
    private struct Header: Decodable {
        // app names the app that wrote the file.
        let app: String
        // version is the file format version.
        let version: Int
    }
}
