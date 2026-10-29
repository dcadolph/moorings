import MooringsCore
import MooringsEngine

extension Scenarios {
    // reloadOnFileChange pins a window at the 40 percent strip, then writes choices with a 30 percent
    // left strip twice. The control writes them through the engine's own store, which records the
    // write, so no pass may reload them and the pin stays put for 1.5 s. The change writes the same
    // choices from outside the store, as a person editing the file would, and proves the choices are
    // reloaded once and the pin reads back at the new strip within 2 s, 1 point. A reload is seen as
    // the loss of a marker kept only in the engine's choices in memory.
    static func reloadOnFileChange(_ s: Stage) {
        guard let (pad, strip, _) = s.pin(), let wide = s.wide() else { return }
        var narrow = s.engine.anchors.choices
        narrow.widths = Widths(left: 30, right: widths.right)
        var newStrip = Geometry.regions(wide, 30, widths.right).left
        newStrip.w += s.skew
        s.note("new strip", newStrip)
        if abs(newStrip.w - strip.w) <= 1 {
            s.fail(
                "the new strip is more than 1 point narrower", "both \(Int(strip.w)) wide, so the check proves nothing")
            return
        }
        guard let payload = try? Choices.encode(narrow) else {
            s.fail("the narrower choices encode", "Choices.encode threw")
            return
        }
        let marker = "scenario.reload.marker"
        let marked = { s.engine.anchors.choices.ignores.contains(marker) }
        s.engine.anchors.choices.ignores.append(marker)
        do {
            try s.engine.platform.store.save(narrow)
        } catch {
            s.fail("the store saves the control write", "\(error)")
            return
        }
        s.engine.wake()
        s.hold(1.5)
        s.note("after control", s.frame(pad.id))
        s.measure("control write reloaded \(marked() ? "no" : "yes")")
        if !marked() {
            s.fail("a write the store made itself is not reloaded in 1.5 s", "the choices were reloaded")
            return
        }
        if !Contract.near(s.frame(pad.id), strip) {
            s.fail(
                "the pin stays at its strip after the control write, 1 point",
                "strip \(strip), pin \(Contract.show(s.frame(pad.id)))")
            return
        }
        let t0 = s.host.now
        guard s.host.spoilChoices(payload) else {
            s.skip("host cannot write the choices from outside")
            return
        }
        s.engine.wake()
        let moved = s.host.wait(until: t0 + placeSeconds) { !marked() && Contract.near(s.frame(pad.id), newStrip) }
        s.note("after change", s.frame(pad.id))
        guard moved else {
            s.fail(
                "a changed file is reloaded and the pin reads back at the new strip within 2 s, 1 point",
                "reloaded \(!marked()), new strip \(newStrip), pin \(Contract.show(s.frame(pad.id)))")
            return
        }
        s.measure("change reloaded and placed \(Scenarios.seconds(s.host.now - t0)) s after the write")
        s.engine.anchors.choices.ignores.append(marker)
        s.engine.wake()
        s.hold(1.5)
        if !marked() {
            s.fail("a changed file is reloaded once, none in the next 1.5 s", "reloaded again")
        }
    }
}
