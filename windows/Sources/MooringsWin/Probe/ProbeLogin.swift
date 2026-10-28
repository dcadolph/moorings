import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeLogin chooses Launch at login once through the tray's command and prints whether the Run key
// now holds Moorings and the command it holds.
func probeLogin(_: ProbeOptions) -> Int32 {
    let tray = Tray(app: App(store: Store()))
    print("before: \(LoginItem.enabled)")
    tray.perform(.atLogin)
    print("after: \(LoginItem.enabled)")
    print("executable: \(LoginItem.executable)")
    return 0
}
