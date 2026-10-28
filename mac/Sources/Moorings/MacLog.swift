import os

import MooringsEngine

// MacLog is the Mac Log: one unified log category per LogCategory under the moorings subsystem.
final class MacLog: Log {
    // subsystem is the unified log subsystem every line goes under.
    static let subsystem = "com.dcadolph.moorings"
    // loggers holds the logger for each category.
    private let loggers: [LogCategory: Logger]

    // init makes a logger per category.
    init() {
        loggers = Dictionary(
            uniqueKeysWithValues: LogCategory.allCases.map {
                ($0, Logger(subsystem: Self.subsystem, category: Self.name($0)))
            })
    }

    // name returns the unified log category for category. Pass lines stay under anchors, where they
    // always went.
    static func name(_ category: LogCategory) -> String {
        category == .passes ? "anchors" : category.rawValue
    }

    // note writes line at notice level under category.
    func note(_ category: LogCategory, _ line: String) {
        loggers[category]?.notice("\(line, privacy: .public)")
    }
}
