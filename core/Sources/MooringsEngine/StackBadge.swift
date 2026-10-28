import MooringsCore

// StackBadge counts the windows stacked under a resting pointer and shows the count on the stack's
// front window, so a person sees how many windows cycle-stacked-windows steps through.
public final class StackBadge {
    // restMove is the most in points the pointer may move between two ticks and still count as
    // resting.
    public static let restMove = 2.0

    // view paints the badge.
    private let view: any BadgeView
    // pointer is the pointer position at the previous tick.
    private var pointer: Point?
    // settled reports whether the badge was already worked out for the current rest.
    private var settled = false

    // init builds a badge painted by view.
    public init(view: any BadgeView) {
        self.view = view
    }

    // update runs once a tick with the pointer at p, in top-left coordinates. Any move of more than
    // restMove hides the badge and restarts the rest. On the first tick of a rest it shows the count
    // of the stack whose front window has its top-left corner under the pointer, or hides the badge
    // when there is none. frames lists the visible windows front to back and is read once per rest,
    // never while the pointer moves or stays still. A mouse button down hides the badge.
    public func update(
        pointer p: Point, buttonDown: Bool, frames: () -> [Frame], palette: Palette,
        choices: StackChoices, gap: Double
    ) {
        guard !buttonDown else {
            hide()
            pointer = nil
            return
        }
        defer { pointer = p }
        guard let last = pointer, abs(p.x - last.x) <= Self.restMove, abs(p.y - last.y) <= Self.restMove else {
            hide()
            settled = false
            return
        }
        guard !settled else { return }
        settled = true
        let list = frames()
        guard let i = Tile.hovered(at: p, frames: list, gap: gap) else { return }
        let n = Tile.stack(anchorOf: i, among: list, choices: choices).count
        if n > 1 {
            view.show(n, at: list[i], palette: palette)
        }
    }

    // hide takes the badge off screen.
    public func hide() {
        view.hide()
    }
}
