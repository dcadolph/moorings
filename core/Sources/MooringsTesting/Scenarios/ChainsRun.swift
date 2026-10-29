import MooringsCore
import MooringsEngine

extension Scenarios {
    // chainsRun saves two chains of left-half then first-third with repeat cycling off: Halves loops
    // and Once does not. It runs each three times on a free window from the same start frame and
    // proves Halves lands on the left half, the left third and the left half again, and Once on the
    // left half, the left third and the left third again, each within 1 s, 1 point.
    static func chainsRun(_ s: Stage) {
        let steps = ["left-half", "first-third"]
        let halves = Chain(name: "Halves", steps: steps, loops: true)
        let once = Chain(name: "Once", steps: steps, loops: false)
        s.choose {
            $0.behavior.subsequentExecution = SubsequentExecution.none
            $0.chains = [halves, once]
        }
        guard let wide = s.wide(), let pad = s.open("window") else { return }
        let start = Frame(x: wide.x + 200, y: wide.y + 150, w: 500, h: 350)
        let screens = s.host.screens()
        let reset = { () -> WindowInfo? in
            s.engine.platform.windows.move(pad.id, to: start, from: nil, behavior: Behaviors())
            s.engine.platform.windows.raise(pad.id)
            guard s.host.wait(until: s.host.now + 1, { Contract.near(s.frame(pad.id), start) }) else {
                s.fail("the window reads back at its start frame within 1 s", "\(Contract.show(s.frame(pad.id)))")
                return nil
            }
            return s.engine.platform.windows.scan(screens, full: true).windows.first { $0.id == pad.id }
        }
        guard let w = reset(), let half = s.engine.actions.preview("left-half", for: w, screens: screens),
            let third = s.engine.actions.preview("first-third", for: w, screens: screens)
        else {
            s.fail("the engine previews left-half and first-third", "no preview for window \(pad.id)")
            return
        }
        s.note("left half", half)
        s.note("left third", third)
        if Contract.near(half, third) {
            s.fail("the left half and the left third differ by more than 1 point", "both \(half)")
            return
        }
        for (chain, want) in [(halves, [half, third, half]), (once, [half, third, third])] {
            if !s.engine.actions.supports(chain.actionName) {
                s.fail("the engine runs a saved chain", "\(chain.actionName) not supported")
                return
            }
            guard reset() != nil else { return }
            for (k, f) in want.enumerated() {
                let ran = s.engine.actions.run(chain.actionName, window: pad.id)
                let landed = s.host.wait(until: s.host.now + 1) { Contract.near(s.frame(pad.id), f) }
                s.note("\(chain.name) press \(k + 1)", s.frame(pad.id))
                if !landed {
                    s.fail(
                        "\(chain.name) press \(k + 1) lands on its step within 1 s, 1 point",
                        "ran \(ran), want \(f), window \(Contract.show(s.frame(pad.id)))")
                    return
                }
            }
        }
    }
}
