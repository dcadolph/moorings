import WinSDK

import MooringsCore

extension Modifiers {
    // keys pairs each key with the virtual keys that hold it: the side-free keys, Win as Command, and
    // the right-hand keys. Windows has no Fn key to read.
    static let keys: [(Modifiers, [Int32])] = [
        (.shift, [0x10]), (.control, [0x11]), (.option, [0x12]), (.command, [0x5B, 0x5C]),
        (.rightShift, [0xA1]), (.rightControl, [0xA3]), (.rightOption, [0xA5]), (.rightCommand, [0x5C]),
    ]

    // init reads the keys held through down, which reports whether a virtual key is down.
    init(down: (Int32) -> Bool) {
        self = []
        for (key, vks) in Self.keys where vks.contains(where: down) {
            insert(key)
        }
    }

    // now reads the keys held at this moment.
    static func now() -> Modifiers {
        Modifiers { GetAsyncKeyState($0) < 0 }
    }
}
