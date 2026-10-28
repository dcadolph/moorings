import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

// probeHold takes Ctrl+Alt+Left for the given seconds, the way another program would, and prints
// whether it got the chord and how many presses reached it: the hotkeys probe's negative control.
func probeHold(_ opts: ProbeOptions) -> Int32 {
    let held = RegisterHotKey(nil, 1, heldChord.mods | WinHotkeys.noRepeat, heldChord.vk)
    print("held: \(held)")
    var got = 0
    pump(until: App.now + opts.seconds) { msg in
        if msg.message == UINT(WM_HOTKEY) {
            got += 1
        }
    }
    if held {
        _ = UnregisterHotKey(nil, 1)
    }
    print("hotkeys received: \(got)")
    return 0
}
