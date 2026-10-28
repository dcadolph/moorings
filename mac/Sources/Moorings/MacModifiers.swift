import CoreGraphics

import MooringsCore

extension Modifiers {
    // sideFree pairs each side-free key with its device-independent bit in a CGEventFlags value.
    static let sideFree: [(Modifiers, UInt64)] = [
        (.shift, CGEventFlags.maskShift.rawValue), (.control, CGEventFlags.maskControl.rawValue),
        (.option, CGEventFlags.maskAlternate.rawValue), (.command, CGEventFlags.maskCommand.rawValue),
        (.function, CGEventFlags.maskSecondaryFn.rawValue),
    ]
    // rightHand pairs each right-hand key with its device-dependent bit, the NX_DEVICER*KEYMASK values
    // CGEventFlags carries in its low bits.
    static let rightHand: [(Modifiers, UInt64)] = [
        (.rightShift, 0x04), (.rightControl, 0x2000), (.rightOption, 0x40), (.rightCommand, 0x10),
    ]

    // init reads the keys a CGEventFlags value holds, right-hand bits included.
    init(flags: CGEventFlags) {
        self = []
        for (key, bit) in Self.sideFree + Self.rightHand where flags.rawValue & bit != 0 {
            insert(key)
        }
    }
}
