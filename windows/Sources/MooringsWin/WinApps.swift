import Foundation
import WinSDK

import MooringsEngine

// WinApps is the Windows Apps: names from the slot identity, and opens through ShellExecuteW, an
// image path directly and a packaged app through its shell:AppsFolder entry.
final class WinApps: Apps {
    // name returns the name to show for the app with bundle, an image path or a user model id.
    func name(_ bundle: String) -> String {
        Tray.appName(bundle)
    }

    // open starts the app with bundle, passing target as its argument when there is one. A
    // background open shows the window without activating it. It returns false when bundle is a
    // path to no file or ShellExecuteW cannot start it.
    func open(_ bundle: String, background: Bool, target: String?) -> Bool {
        let packaged = bundle.contains("!")
        guard packaged || FileManager.default.fileExists(atPath: bundle) else {
            FileHandle.standardError.write(Data("apps: open \(bundle): no such file\n".utf8))
            return false
        }
        let file = packaged ? "shell:AppsFolder\\" + bundle : bundle
        let show = background ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL
        let result =
            if let target {
                ShellExecuteW(nil, wide("open"), wide(file), wide(target), nil, show)
            } else {
                ShellExecuteW(nil, wide("open"), wide(file), nil, nil, show)
            }
        guard Int(bitPattern: result) > 32 else {
            FileHandle.standardError.write(Data("apps: open \(bundle) failed: \(Int(bitPattern: result))\n".utf8))
            return false
        }
        return true
    }
}
