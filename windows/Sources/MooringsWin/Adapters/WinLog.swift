import Foundation

import MooringsEngine

// WinLog is the Windows Log: each line on stderr after its category, as the probes read them, and
// the same line at the end of the log file a report attaches.
final class WinLog: Log {
    // heard is told each line after it is written, for the probes that count lines.
    var heard: (LogCategory, String) -> Void = { _, _ in }

    // note writes line to stderr and to the log file as "category: line".
    func note(_ category: LogCategory, _ line: String) {
        let text = "\(category.rawValue): \(line)\n"
        FileHandle.standardError.write(Data(text.utf8))
        LogFile.shared?.append(text)
        heard(category, line)
    }
}

// LogFile is moorings.log in a folder and the one older file beside it. A log that reaches limit
// bytes moves to moorings.log.1, replacing the one there, so the two never pass twice the limit.
final class LogFile: @unchecked Sendable {
    // limit is the size at which the log moves aside, 1 MB.
    static let limit: UInt64 = 1 << 20
    // shared is the app's log in %LOCALAPPDATA%\Moorings, nil when LOCALAPPDATA is unset.
    static let shared: LogFile? = folder().map { LogFile(folder: $0) }

    // url is the log file.
    let url: URL
    // older is where the log moves once it reaches limit.
    let older: URL
    // lock keeps the lines of two threads whole and in order.
    private let lock = NSLock()

    // init names the log files in folder. Nothing is written until the first line.
    init(folder: URL) {
        url = folder.appendingPathComponent("moorings.log")
        older = folder.appendingPathComponent("moorings.log.1")
    }

    // folder returns %LOCALAPPDATA%\Moorings, nil when LOCALAPPDATA is unset or empty.
    static func folder() -> URL? {
        guard let base = ProcessInfo.processInfo.environment["LOCALAPPDATA"], !base.isEmpty else { return nil }
        return URL(fileURLWithPath: base).appendingPathComponent("Moorings")
    }

    // append writes text at the end of the log, creating the folder and the file on the first line
    // and moving a log at limit aside first. A line the disk refuses is dropped from the file only,
    // since it is already on stderr and there is nowhere else to say so.
    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var handle = open() else { return }
        if let end = try? handle.seekToEnd(), end >= Self.limit {
            try? handle.close()
            try? FileManager.default.removeItem(at: older)
            try? FileManager.default.moveItem(at: url, to: older)
            guard let fresh = open() else { return }
            handle = fresh
        }
        try? handle.write(contentsOf: Data(text.utf8))
        try? handle.close()
    }

    // tail returns the last n lines of the older file and the log read together, oldest first.
    func tail(_ n: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let read = { (u: URL) in (try? String(contentsOf: u, encoding: .utf8)) ?? "" }
        let lines = (read(older) + read(url)).split(separator: "\n").map(String.init)
        return Array(lines.suffix(n))
    }

    // open returns a handle at the end of the log, creating the folder and the file when missing,
    // nil when the disk refuses either.
    private func open() -> FileHandle? {
        let files = FileManager.default
        if !files.fileExists(atPath: url.path) {
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard files.createFile(atPath: url.path, contents: nil) else { return nil }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        _ = try? handle.seekToEnd()
        return handle
    }
}
