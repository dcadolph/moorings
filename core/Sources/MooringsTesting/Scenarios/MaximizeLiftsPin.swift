import MooringsCore
import MooringsEngine

extension Scenarios {
    // maximizeLiftsPin runs Maximize on a focused pin and proves it lifts over its strip and the channel
    // within 1.5 s, and that Maximize again lowers it into its strip within 1.5 s, both within 1 point.
    // The lift spans the strips in use, as the lift probe measured it: a side with no anchored app gives
    // its strip to the lift.
    static func maximizeLiftsPin(_ s: Stage) {
        guard let (pad, strip, _) = s.pin(), let wide = s.wide() else { return }
        let use = s.engine.anchors.inUse(wide)
        let over = Geometry.lift(wide, .left, use.left, use.right)
        s.note("over", over)
        if over.w <= strip.w {
            s.fail("the lifted frame is wider than the strip", "over \(over), strip \(strip)")
            return
        }
        let screens = s.host.screens()
        s.engine.platform.windows.raise(pad.id)
        let focused = s.host.wait(until: s.host.now + 1) {
            s.engine.platform.windows.scan(screens, full: true).focused?.id == pad.id
        }
        guard focused else {
            s.fail("raise makes the pin focused within 1 s", "pin \(pad.id) not focused")
            return
        }
        for (step, want) in [
            ("lifts the pin over its strip and the channel", over), ("again lowers it into its strip", strip),
        ] {
            let t = s.host.now
            let ran = s.engine.actions.run("maximize")
            let landed = s.host.wait(until: t + 1.5) { Contract.near(s.frame(pad.id), want) }
            s.note(want == over ? "lifted" : "lowered", s.frame(pad.id))
            guard ran, landed else {
                s.fail(
                    "maximize \(step) within 1.5 s, 1 point",
                    "ran \(ran), want \(want), pin \(Contract.show(s.frame(pad.id)))")
                return
            }
        }
    }
}
