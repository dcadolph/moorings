import Foundation

import MooringsEngine

// WinLog is the Windows Log: each line on stderr after its category, as the probes read them.
final class WinLog: Log {
    // heard is told each line after it is written, for the probes that count lines.
    var heard: (LogCategory, String) -> Void = { _, _ in }

    // note writes line to stderr as "category: line".
    func note(_ category: LogCategory, _ line: String) {
        FileHandle.standardError.write(Data("\(category.rawValue): \(line)\n".utf8))
        heard(category, line)
    }
}
