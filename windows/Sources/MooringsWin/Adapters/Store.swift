import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// Store keeps the choices in a JSON file, the same shape the Mac app saves.
final class Store: ChoicesStore {
    // url is the choices file.
    let url: URL
    // stamp is the file's last write time as of the last load or save, nil when there was no file.
    private(set) var stamp: UInt64?

    // init uses %APPDATA%\Moorings\choices.json.
    convenience init() {
        let base = ProcessInfo.processInfo.environment["APPDATA"] ?? NSTemporaryDirectory()
        self.init(
            url: URL(fileURLWithPath: base, isDirectory: true)
                .appendingPathComponent("Moorings", isDirectory: true)
                .appendingPathComponent("choices.json"))
    }

    // init keeps the choices in the file at url.
    init(url: URL) {
        self.url = url
    }

    // aside is where load moves a choices file it cannot read: choices.json.bad beside it.
    var aside: URL { url.appendingPathExtension("bad") }

    // load returns the saved choices, or the defaults when there is no file. A file it cannot read
    // moves to aside, replacing an older one there, and loads as the defaults with the reason.
    func load() -> Loaded {
        defer { stamp = writeTime() }
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(choices: Choices()) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return Loaded(choices: Choices(), fallback: "choices.json not read: \(error)")
        }
        let loaded = Choices.decode(data)
        guard let reason = loaded.fallback else { return loaded }
        do {
            try? FileManager.default.removeItem(at: aside)
            try FileManager.default.moveItem(at: url, to: aside)
        } catch {
            return Loaded(choices: loaded.choices, fallback: "\(reason), and it stayed in place: \(error)")
        }
        return loaded
    }

    // changed reports whether the file's last write time differs from the one kept.
    func changed() -> Bool {
        writeTime() != stamp
    }

    // writeTime reads the file's last write time as a FILETIME count, nil when it cannot be read.
    func writeTime() -> UInt64? {
        var data = WIN32_FILE_ATTRIBUTE_DATA()
        let ok = withUnsafeMutablePointer(to: &data) {
            GetFileAttributesExW(wide(url.path), GetFileExInfoStandard, $0)
        }
        guard ok == true else { return nil }
        return UInt64(data.ftLastWriteTime.dwHighDateTime) << 32
            | UInt64(data.ftLastWriteTime.dwLowDateTime)
    }

    // setWriteTime sets the file's last write time to time, a FILETIME count, and reports whether
    // it took. The kept stamp is left alone.
    func setWriteTime(_ time: UInt64) -> Bool {
        let share = DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE)
        let handle = CreateFileW(
            wide(url.path), DWORD(0x100), share, nil, DWORD(OPEN_EXISTING),
            DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        guard let handle, handle != INVALID_HANDLE_VALUE else { return false }
        defer { _ = CloseHandle(handle) }
        var ft = FILETIME(dwLowDateTime: DWORD(time & 0xFFFF_FFFF), dwHighDateTime: DWORD(time >> 32))
        return SetFileTime(handle, nil, nil, &ft) == true
    }

    // save writes choices, creating the folder on first use.
    func save(_ choices: Choices) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Choices.encode(choices).write(to: url, options: .atomic)
        stamp = writeTime()
    }
}
