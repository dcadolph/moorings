import MooringsCore
import MooringsEngine

extension Scenarios {
    // dropPastDesktop pauses the passes and moves a window through the store to the left strip, the
    // right strip and the whole usable area of the ultrawide, each strip 40 percent of it, and proves
    // each reads back within 1 point. On a fake ultrawide wider than the desktop the frames lie past
    // it, where a drop on the simulated screen puts a window.
    static func dropPastDesktop(_ s: Stage) {
        guard let wide = s.wide() else { return }
        s.choose { $0.paused = true }
        guard let pad = s.open("moved window") else { return }
        let side = (wide.w * 0.4).rounded(.down)
        let frames = [
            ("left strip", Frame(x: wide.x, y: wide.y, w: side, h: wide.h)),
            ("right strip", Frame(x: wide.x + wide.w - side, y: wide.y, w: side, h: wide.h)),
            ("whole usable area", wide),
        ]
        for (label, f) in frames {
            s.engine.platform.windows.move(pad.id, to: f, from: s.frame(pad.id), behavior: Behaviors())
            let read = s.host.wait(until: s.host.now + 1) { Contract.near(s.frame(pad.id), f) }
            s.note(label, s.frame(pad.id))
            if !read {
                s.fail(
                    "the store moves a window to the \(label) and reads it back within 1 s, 1 point",
                    "want \(f), window \(Contract.show(s.frame(pad.id)))")
            }
        }
    }
}
