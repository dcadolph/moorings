// ScreenQuirks holds what an action needs to know about the displays beyond their frames.
public struct ScreenQuirks: Equatable, Sendable {
    // notched lists the screens with a camera notch.
    public var notched: Set<Int>
    // staged lists the screens showing the Stage Manager strip.
    public var staged: Set<Int>
    // stageOnRight reports whether the Stage Manager strip sits on the right.
    public var stageOnRight: Bool

    // none is a platform with no notch and no Stage Manager.
    public static let none = ScreenQuirks()

    // init builds the quirks; every field defaults to absent.
    public init(notched: Set<Int> = [], staged: Set<Int> = [], stageOnRight: Bool = false) {
        self.notched = notched
        self.staged = staged
        self.stageOnRight = stageOnRight
    }
}
