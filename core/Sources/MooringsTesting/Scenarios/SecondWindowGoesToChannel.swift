import MooringsCore
import MooringsEngine

extension Scenarios {
    // secondWindowGoesToChannel opens a second window of a pinned app with slot stacks off, puts it on
    // the strip by hand, and proves the pass pushes it inside the channel within 1 s.
    static func secondWindowGoesToChannel(_ s: Stage) {
        guard let (_, strip, _) = s.pin(), let wide = s.wide(), let second = s.open("second window") else { return }
        let channel = s.regions(wide).channel
        s.note("channel", channel)
        let onStrip = Frame(x: strip.x + 10, y: strip.y + 10, w: 300, h: 300)
        guard s.place(second.id, at: onStrip, "second window on the strip") else { return }
        let tp = s.host.now
        let inside = { (f: Frame?) -> Bool in
            guard let f else { return false }
            return f.x >= channel.x - 1 && f.x + f.w <= channel.x + channel.w + 1
        }
        let pushed = s.host.wait(until: tp + reactSeconds) { inside(s.frame(second.id)) }
        s.note("second", s.frame(second.id))
        guard pushed else {
            s.fail(
                "a second window of a pinned app is pushed inside the channel within 1 s",
                "channel \(channel), second \(Contract.show(s.frame(second.id)))")
            return
        }
        if let move = s.moves.first(where: { $0.id == second.id && $0.t >= tp }) {
            s.measure("second window pushed \(seconds(move.t - tp)) s after landing on the strip")
        }
    }
}
