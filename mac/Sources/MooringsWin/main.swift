import Foundation
import WinSDK

// Per-Monitor-V2 must be set before any window call, so frames come back in physical pixels.
_ = SetProcessDpiAwarenessContext(perMonitorAwareV2)

let options: ProbeOptions
do {
    options = try ProbeOptions(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("MooringsWin: \(error)\n".utf8))
    exit(2)
}

guard let name = options.probe else {
    print("MooringsWin \(version): no tray yet")
    exit(0)
}
guard let probe = probes[name] else {
    FileHandle.standardError.write(Data("MooringsWin: unknown probe \(name)\n".utf8))
    exit(2)
}
exit(probe(options))
