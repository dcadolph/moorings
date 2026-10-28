// Modifiers is the set of modifier keys held, spelled the same on every platform. A right-hand bit is
// set only while that side's key is down, beside the side-free bit the key also sets, so a trigger can
// tell Right Option from Left Option.
public struct Modifiers: OptionSet, Hashable, Sendable {
    // rawValue holds one bit per key.
    public let rawValue: UInt16

    // init builds a set from its bits.
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    // shift is either Shift key.
    public static let shift = Modifiers(rawValue: 1 << 0)
    // control is either Control key.
    public static let control = Modifiers(rawValue: 1 << 1)
    // option is either Option key, Alt on Windows.
    public static let option = Modifiers(rawValue: 1 << 2)
    // command is either Command key, the Windows key on Windows.
    public static let command = Modifiers(rawValue: 1 << 3)
    // function is the Fn key, which Windows never reports.
    public static let function = Modifiers(rawValue: 1 << 4)
    // rightShift is the right Shift key.
    public static let rightShift = Modifiers(rawValue: 1 << 5)
    // rightControl is the right Control key.
    public static let rightControl = Modifiers(rawValue: 1 << 6)
    // rightOption is the right Option key.
    public static let rightOption = Modifiers(rawValue: 1 << 7)
    // rightCommand is the right Command key.
    public static let rightCommand = Modifiers(rawValue: 1 << 8)

    // names pairs each side-free key with the name the saved choices use for it.
    static let names: [(Modifiers, String)] = [
        (.shift, "shift"), (.control, "control"), (.option, "option"), (.command, "command"),
    ]

    // keys pairs each shortcut modifier with its key.
    static let keys: [(Modifier, Modifiers)] = [(.shift, .shift), (.ctrl, .control), (.alt, .option), (.cmd, .command)]

    // init builds the set a shortcut's modifiers hold.
    public init(_ mods: [Modifier]) {
        self = []
        for (mod, key) in Self.keys where mods.contains(mod) {
            insert(key)
        }
    }

    // init builds the set named by the saved choices' modifier names, nil when a name is unknown, since
    // no key can hold it.
    public init?(names: [String]) {
        var m = Modifiers()
        for name in names {
            guard let key = Self.names.first(where: { $0.1 == name })?.0 else { return nil }
            m.insert(key)
        }
        self = m
    }

    // shortcut lists the shortcut modifiers among the side-free keys held, in menu order.
    public var shortcut: [Modifier] {
        Self.keys.filter { contains($0.1) }.map(\.0).sorted()
    }
}
