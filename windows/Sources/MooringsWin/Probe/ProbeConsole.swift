import Foundation
import WinSDK

// consoleMarker is the line the console probe prints and then looks for on the terminal's screen.
private let consoleMarker = "console marker line"

// probeConsole writes to stdout and stderr the way the app does, then saves what the process holds
// to console.txt in the --report folder, since a process with no terminal has nowhere else to say.
func probeConsole(_ opts: ProbeOptions) -> Int32 {
    print(consoleMarker)
    fflush(stdout)
    FileHandle.standardError.write(Data("console: stderr written\n".utf8))
    let lines = [
        "window: \(GetConsoleWindow() == nil ? "none" : "present")",
        "stdout: \(streamKind(1))",
        "stderr: \(streamKind(2))",
        "screen: \(screenHolds(consoleMarker) ? "marker" : "no marker")",
    ]
    do {
        let folder = URL(fileURLWithPath: opts.report)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try lines.joined(separator: "\r\n").write(
            to: folder.appendingPathComponent("console.txt"), atomically: true, encoding: .utf8)
        return 0
    } catch {
        return 1
    }
}

// streamKind names where descriptor leads: console, nul, pipe, file, or none.
private func streamKind(_ descriptor: Int32) -> String {
    guard let handle = standardHandle(descriptor) else { return "none" }
    switch GetFileType(handle) {
    case DWORD(FILE_TYPE_CHAR):
        var mode: DWORD = 0
        return GetConsoleMode(handle, &mode) ? "console" : "nul"
    case DWORD(FILE_TYPE_PIPE):
        return "pipe"
    default:
        return "file"
    }
}

// screenHolds reports whether text is on the attached console's screen, reading the cells down to
// the cursor. It is false with no console.
private func screenHolds(_ text: String) -> Bool {
    // access is GENERIC_READ and GENERIC_WRITE, whose macros are too wide to import as DWORD.
    let access = DWORD(0xC000_0000)
    let share = DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE)
    let screen = CreateFileW(wide("CONOUT$"), access, share, nil, DWORD(OPEN_EXISTING), 0, nil)
    guard let screen, screen != INVALID_HANDLE_VALUE else { return false }
    defer { CloseHandle(screen) }
    var info = CONSOLE_SCREEN_BUFFER_INFO()
    guard GetConsoleScreenBufferInfo(screen, &info) else { return false }
    let count = Int(info.dwSize.X) * (Int(info.dwCursorPosition.Y) + 1)
    var cells = [WCHAR](repeating: 0, count: count)
    var read: DWORD = 0
    guard ReadConsoleOutputCharacterW(screen, &cells, DWORD(count), COORD(X: 0, Y: 0), &read) else {
        return false
    }
    return String(decoding: cells.prefix(Int(read)), as: UTF16.self).contains(text)
}
