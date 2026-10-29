import MooringsCore
import MooringsEngine

extension Scenarios {
    // everyKeymapAction binds the default keymap and runs every action in keymapActions once on a free
    // window from the same start frame, and proves each lands within 1 point of the frame the engine's
    // preview gave for it, at least 20 of them. An app's least size may hold a window larger than a
    // small cell, and then either edge in that range counts. It also proves the list names every
    // action of the keymap and the Window families that previews a frame, so an action added or
    // dropped there shows here.
    static func everyKeymapAction(_ s: Stage) {
        s.choose { _ in }
        guard let wide = s.wide(), let pad = s.open("window") else { return }
        let start = Frame(x: wide.x + 200, y: wide.y + 150, w: 500, h: 350)
        let move = { (f: Frame) in
            s.engine.platform.windows.move(pad.id, to: f, from: nil, behavior: Behaviors())
        }
        move(Frame(x: start.x, y: start.y, w: 1, h: 1))
        _ = s.host.wait(until: s.host.now + 0.3) { false }
        guard let least = s.frame(pad.id) else {
            s.fail("the store reads the window at its least size", "window \(pad.id) gone")
            return
        }
        s.measure("least size \(Int(least.w)) \(Int(least.h))")
        if least.w > 300 || least.h > 300 {
            s.fail("the window's least size is at most 300 points a side", "least \(least.w) \(least.h)")
            return
        }
        let screens = s.host.screens()
        var previewed: Set<String> = []
        var landed = 0
        var worst = 0.0
        for name in candidates(s.engine) {
            move(start)
            s.engine.platform.windows.raise(pad.id)
            let ready = s.host.wait(until: s.host.now + 1) { Contract.near(s.frame(pad.id), start) }
            guard ready,
                let w = s.engine.platform.windows.scan(screens, full: true).windows.first(where: { $0.id == pad.id })
            else {
                s.fail(
                    "the window reads back at its start frame within 1 s", "\(name): \(Contract.show(s.frame(pad.id)))")
                return
            }
            guard let want = s.engine.actions.preview(name, for: w, screens: screens) else { continue }
            previewed.insert(name)
            guard keymapActions.contains(name) else { continue }
            let ran = s.engine.actions.run(name, window: pad.id)
            var off = Double.infinity
            _ = s.host.wait(until: s.host.now + 1) {
                off = s.frame(pad.id).map { landedOff(want, $0, least: least) } ?? .infinity
                return off <= 1
            }
            worst = max(worst, off)
            if off > 1 {
                s.fail(
                    "every action lands within 1 point of the engine's preview within 1 s",
                    "\(name): ran \(ran), want \(want), got \(Contract.show(s.frame(pad.id)))")
            } else {
                landed += 1
            }
        }
        s.measure("\(landed) actions landed of \(keymapActions.count) listed, worst off \(Int(worst.rounded()))")
        let listed = Set(keymapActions)
        let onOne = previewed.subtracting(crossing)
        if listed != onOne {
            s.fail(
                "the list names every action that previews a frame on one screen, \(onOne.count) previewed",
                "\(listed.count) listed; unlisted \(onOne.subtracting(listed).sorted()), "
                    + "no preview \(listed.subtracting(onOne).sorted())")
        }
        if landed < 20 {
            s.fail("at least 20 actions land within 1 point of the engine's preview", "\(landed) landed")
        }
    }

    // candidates lists the default keymap's actions and the Window families' actions the engine runs
    // itself, leaving out the routed ones and the front app's, which move no frame.
    static func candidates(_ engine: Engine) -> [String] {
        let family = ActionRunner.families.flatMap { $0.names + $0.groups.flatMap(\.names) }
        return Set(Bindings(Choices()).map.keys).union(family).filter {
            !engine.actions.routed($0) && !Keymaps.windowNames.contains($0)
        }.sorted()
    }

    // landedOff returns how far got is off want on its worst edge. Where want is under the least size
    // on an axis, the window keeps the least size and its near edge may shift back by the difference
    // to stay on the screen, so either edge in that range is on.
    static func landedOff(_ want: Frame, _ got: Frame, least: Frame) -> Double {
        let (dx, dw) = axisOff(want.x, want.w, got.x, got.w, least: least.w)
        let (dy, dh) = axisOff(want.y, want.h, got.y, got.h, least: least.h)
        return max(dx, dy, dw, dh)
    }

    // axisOff returns how far one axis of a landed frame is off the wanted one, the edge and the length.
    static func axisOff(_ want: Double, _ wantLen: Double, _ got: Double, _ gotLen: Double, least: Double)
        -> (Double, Double)
    {
        guard wantLen < least - 1 else {
            return (abs(want - got), abs(wantLen - gotLen))
        }
        let slack = least - wantLen
        let edge = got > want ? got - want : got < want - slack ? want - slack - got : 0
        return (edge, abs(least - gotLen))
    }

    // crossing lists the actions that send a window to another screen, which preview a frame only on a
    // host with more than one, so the list leaves them out.
    static let crossing = Set(["previous-display", "next-display"] + Actions.displayNames)

    // keymapActions lists every action everyKeymapAction runs: each one of the default keymap and the Window
    // families that previews a frame on one screen, 124 of them.
    static let keymapActions: [String] = [
        "almost-maximize", "bottom-center-left-eighth", "bottom-center-left-sixteenth",
        "bottom-center-left-twelfth", "bottom-center-ninth", "bottom-center-right-eighth",
        "bottom-center-right-sixteenth", "bottom-center-right-twelfth", "bottom-center-sixth", "bottom-half",
        "bottom-left", "bottom-left-eighth", "bottom-left-ninth", "bottom-left-sixteenth", "bottom-left-sixth",
        "bottom-left-third", "bottom-left-twelfth", "bottom-right", "bottom-right-eighth", "bottom-right-ninth",
        "bottom-right-sixteenth", "bottom-right-sixth", "bottom-right-third", "bottom-right-twelfth",
        "bottom-vertical-third", "bottom-vertical-two-thirds", "center", "center-half", "center-prominently",
        "center-third", "center-three-fourths", "center-two-thirds", "double-height-down", "double-height-up",
        "double-width-left", "double-width-right", "fifth-vertical-eighth", "fifth-vertical-sixth", "first-fourth",
        "first-third", "first-three-fourths", "first-two-thirds", "first-vertical-eighth", "first-vertical-sixth",
        "fourth-vertical-eighth", "fourth-vertical-sixth", "halve-height-down", "halve-height-up",
        "halve-width-left", "halve-width-right", "larger", "larger-height", "larger-width", "last-fourth",
        "last-third", "last-three-fourths", "last-two-thirds", "last-vertical-eighth", "last-vertical-sixth",
        "left-half", "lower-middle-center-left-sixteenth", "lower-middle-center-right-sixteenth",
        "lower-middle-left-sixteenth", "lower-middle-right-sixteenth", "maximize", "maximize-height",
        "middle-center-left-twelfth", "middle-center-ninth", "middle-center-right-twelfth", "middle-left-ninth",
        "middle-left-twelfth", "middle-right-ninth", "middle-right-twelfth", "middle-vertical-third",
        "move-bottom-left", "move-bottom-right", "move-down", "move-left", "move-right", "move-top-left",
        "move-top-right", "move-up", "right-half", "second-fourth", "second-vertical-eighth",
        "second-vertical-sixth", "seventh-vertical-eighth", "sixth-vertical-eighth", "smaller", "smaller-height",
        "smaller-width", "specified", "third-fourth", "third-vertical-eighth", "third-vertical-sixth",
        "top-center-left-eighth", "top-center-left-sixteenth", "top-center-left-twelfth", "top-center-ninth",
        "top-center-right-eighth", "top-center-right-sixteenth", "top-center-right-twelfth", "top-center-sixth",
        "top-half", "top-left", "top-left-eighth", "top-left-ninth", "top-left-sixteenth", "top-left-sixth",
        "top-left-third", "top-left-twelfth", "top-right", "top-right-eighth", "top-right-ninth",
        "top-right-sixteenth", "top-right-sixth", "top-right-third", "top-right-twelfth", "top-vertical-third",
        "top-vertical-two-thirds", "upper-middle-center-left-sixteenth", "upper-middle-center-right-sixteenth",
        "upper-middle-left-sixteenth", "upper-middle-right-sixteenth",
    ]
}
