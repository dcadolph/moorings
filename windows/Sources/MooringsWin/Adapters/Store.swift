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

    // export writes choices to path as a settings file the Mac imports too.
    static func export(_ choices: Choices, to path: String) throws {
        try SettingsBackup.encode(choices, exported: Date()).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // imported reads the settings file at path, the same shape the Mac exports, refusing another app's
    // file and a newer format. Keys this build does not know are left out.
    static func imported(_ path: String) throws -> Choices {
        try SettingsBackup.decode(try Data(contentsOf: URL(fileURLWithPath: path)))
    }

    // refusal says in plain words why the settings file at path was not imported.
    static func refusal(_ error: Error, _ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        switch error {
        case BackupError.notMoorings(let app):
            return "\(name) holds settings for \(app), not Moorings."
        case BackupError.newerVersion:
            return "\(name) comes from a newer Moorings. Update first."
        case BackupError.unreadable:
            return "\(name) is not a Moorings settings file."
        default:
            return "\(name) was not read: \(error)"
        }
    }
}

// FileDialog asks for a settings file through the Windows common file dialogs.
enum FileDialog {
    // pick shows the save dialog with name filled in when saving, else the open dialog, owned by owner
    // and filtered to JSON files, and returns the path chosen, nil when canceled.
    static func pick(saving: Bool, name: String = "", owner: HWND?) -> String? {
        var filter = Array("Settings files (*.json)\0*.json\0All files (*.*)\0*.*\0\0".utf16)
        var ext = Array("json".utf16) + [0]
        var file = Array(name.utf16) + [UInt16](repeating: 0, count: 1024)
        let flags =
            saving
            ? OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
            : OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
        let ok = filter.withUnsafeMutableBufferPointer { f in
            ext.withUnsafeMutableBufferPointer { e in
                file.withUnsafeMutableBufferPointer { buf in
                    var ofn = OPENFILENAMEW()
                    ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
                    ofn.hwndOwner = owner
                    ofn.lpstrFilter = UnsafePointer(f.baseAddress)
                    ofn.lpstrDefExt = UnsafePointer(e.baseAddress)
                    ofn.lpstrFile = buf.baseAddress
                    ofn.nMaxFile = DWORD(buf.count)
                    ofn.Flags = DWORD(flags)
                    return (saving ? GetSaveFileNameW(&ofn) : GetOpenFileNameW(&ofn)) == true
                }
            }
        }
        guard ok else { return nil }
        return String(decoding: file.prefix { $0 != 0 }, as: UTF16.self)
    }
}
