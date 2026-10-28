import Foundation

import MooringsCore
import MooringsEngine

// Store keeps the choices in a JSON file, the same shape the Mac app saves.
final class Store: ChoicesStore {
    // url is the choices file.
    let url: URL

    // init uses %APPDATA%\Moorings\choices.json.
    init() {
        let base = ProcessInfo.processInfo.environment["APPDATA"] ?? NSTemporaryDirectory()
        url = URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("Moorings", isDirectory: true)
            .appendingPathComponent("choices.json")
    }

    // load returns the saved choices, or the defaults when there is no readable file.
    func load() -> Choices {
        Choices.decode((try? Data(contentsOf: url)) ?? Data())
    }

    // save writes choices, creating the folder on first use.
    func save(_ choices: Choices) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Choices.encode(choices).write(to: url, options: .atomic)
    }
}
