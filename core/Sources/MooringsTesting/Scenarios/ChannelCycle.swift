import MooringsCore
import MooringsEngine

extension Scenarios {
    // channelCycle stacks three free windows in the channel, fills the channel with the first and
    // proves that Control-Left and Right are claimed while a fill is in front: Cycle channel windows
    // fills the channel with the next window and focuses it, and backward brings the first back. A
    // window that does not fill in front, a pause and a Restore of the fill each let the keys go, and
    // a resume with the fill in front claims them again. Each rule holds within 1 s. It cycles only
    // between its own first two windows, so on a host with other windows in the channel none of
    // them is filled.
    static func channelCycle(_ s: Stage) {
        s.choose { _ in }
        let screens = s.host.screens()
        guard let i = screens.ultrawide else {
            s.fail("the host has an ultrawide", "none at the host's min aspect")
            return
        }
        let c = s.engine.organizer.area(screens, i)
        s.note("channel", c)
        let before = (0..<3).map { Frame(x: c.x + 100 + 40 * Double($0), y: c.y + 100, w: 700, h: 500) }
        var pads: [WindowInfo] = []
        for (k, f) in before.enumerated() {
            guard let pad = s.open("window \(k + 1)"), s.place(pad.id, at: f, "window \(k + 1)") else { return }
            pads.append(pad)
        }
        guard s.host.wait(until: s.host.now + 1, { zip(pads, before).allSatisfy { Contract.near(s.frame($0.id), $1) } })
        else {
            s.fail(
                "the store reads the three windows within 1 s, 1 point",
                "want \(before), got \(pads.map { Contract.show(s.frame($0.id)) })")
            return
        }
        let cycle = s.engine.channelCycle
        let claimed = { (want: Bool, rule: String) in
            s.engine.wake()
            if !s.host.wait(until: s.host.now + 1, { cycle.claimed == want }) {
                s.fail(rule, "claimed \(cycle.claimed), focused \(focused(s, screens).map(String.init) ?? "none")")
            }
        }
        s.engine.platform.windows.raise(pads[0].id)
        guard let first = read(s, pads[0].id, screens), s.engine.actions.fill(first, screens: screens),
            let fill = s.frame(pads[0].id)
        else {
            s.fail("the first window fills the channel", "fill refused on \(Contract.show(s.frame(pads[0].id)))")
            return
        }
        s.note("fill", fill)
        claimed(true, "a fill in front claims Control-Left and Right within 1 s")
        s.engine.actions.run("cycle-channel-windows")
        if !s.host.wait(
            until: s.host.now + 1,
            {
                Contract.near(s.frame(pads[1].id), fill) && focused(s, screens) == pads[1].id
            })
        {
            s.fail(
                "cycle channel windows fills the channel with the next window and focuses it within 1 s, 1 point",
                "fill \(fill), second \(Contract.show(s.frame(pads[1].id))), "
                    + "focused \(String(describing: focused(s, screens)))"
            )
        }
        s.note("second", s.frame(pads[1].id))
        s.engine.actions.run("cycle-channel-windows-backward")
        if !s.host.wait(until: s.host.now + 1, { focused(s, screens) == pads[0].id }) {
            s.fail(
                "cycle channel windows backward focuses the first window within 1 s",
                "focused \(String(describing: focused(s, screens)))")
        }
        claimed(true, "the claim stands after a cycle")
        s.engine.platform.windows.raise(pads[2].id)
        claimed(false, "a window that does not fill in front lets the keys go within 1 s")
        s.engine.platform.windows.raise(pads[0].id)
        claimed(true, "the fill in front again claims the keys within 1 s")
        s.choose { $0.paused = true }
        claimed(false, "a pause lets the keys go within 1 s")
        s.choose { _ in }
        s.engine.platform.windows.raise(pads[0].id)
        claimed(true, "a resume with the fill in front claims the keys within 1 s")
        s.engine.actions.run("restore", window: pads[0].id)
        claimed(false, "a Restore of the fill lets the keys go within 1 s")
        s.note("restored", s.frame(pads[0].id))
    }

    // read returns the window with id from a full scan on screens.
    private static func read(_ s: Stage, _ id: WindowID, _ screens: Screens) -> WindowInfo? {
        s.engine.platform.windows.scan(screens, full: true).windows.first { $0.id == id }
    }

    // focused returns the id of the focused window from a scan on screens.
    private static func focused(_ s: Stage, _ screens: Screens) -> WindowID? {
        s.engine.platform.windows.scan(screens, full: false).focused?.id
    }
}
