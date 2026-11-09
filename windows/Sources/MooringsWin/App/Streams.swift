import Foundation
import WinSDK

// standardOutputHandle and standardErrorHandle are STD_OUTPUT_HANDLE and STD_ERROR_HANDLE, whose
// macros are negative numbers cast to DWORD.
private let standardOutputHandle = DWORD(bitPattern: -11)
private let standardErrorHandle = DWORD(bitPattern: -12)

// openStandardStreams gives stdout and stderr somewhere to write. The exe is linked as a Windows
// program so Explorer opens no console for it, which also means it can start with no streams, and
// a write to a missing stderr ends the process. A stream the launcher gave a pipe or a file keeps
// it. A missing one goes to the terminal that started the exe, or to NUL when there is none.
func openStandardStreams() {
    let needOutput = standardHandle(1) == nil
    let needError = standardHandle(2) == nil
    guard needOutput || needError else { return }
    let target = AttachConsole(DWORD.max) ? "CONOUT$" : "NUL"
    if needOutput { reopen(stdout, descriptor: 1, handle: standardOutputHandle, to: target) }
    if needError { reopen(stderr, descriptor: 2, handle: standardErrorHandle, to: target) }
}

// standardHandle returns the Windows handle behind descriptor, nil when it leads nowhere.
func standardHandle(_ descriptor: Int32) -> HANDLE? {
    let raw = _get_osfhandle(descriptor)
    guard raw != -1, raw != -2, let handle = HANDLE(bitPattern: raw) else { return nil }
    return GetFileType(handle) == DWORD(FILE_TYPE_UNKNOWN) ? nil : handle
}

// reopen points the C stream, its descriptor, and its Windows handle at target. print writes through
// the stream, while FileHandle reads the descriptor, and a process with no stream keeps the stream
// off its usual descriptor, so all three are set.
private func reopen(_ stream: UnsafeMutablePointer<FILE>, descriptor: Int32, handle: DWORD, to target: String) {
    var opened: UnsafeMutablePointer<FILE>?
    guard freopen_s(&opened, target, "w", stream) == 0 else { return }
    _dup2(_fileno(stream), descriptor)
    SetStdHandle(handle, HANDLE(bitPattern: _get_osfhandle(descriptor)))
}
