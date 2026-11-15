import MooringsCore
import MooringsEngine

extension Scenarios {
    // profileChord is Control-Option-Shift-F7, the chord the profile scenario binds in both profiles.
    static let profileChord = StoredShortcut(mods: ["ctrl", "alt", "shift"], key: "f7")

    // profileSwitchChangesKeymap saves two profiles that bind one chord, Halves to left-half and Rights
    // to right-half, and proves that a press of the chord after each switch lands the front window on
    // that profile's action, and that switching back to Halves restores left-half, each within 1 s,
    // 1 point. A host that cannot press keys skips it.
    static func profileSwitchChangesKeymap(_ s: Stage) {
        var halves = ProfileSettings()
        halves.shortcuts["left-half"] = profileChord
        var rights = ProfileSettings()
        rights.shortcuts["right-half"] = profileChord
        s.choose {
            $0.profiles = [Profile(name: "Halves", settings: halves), Profile(name: "Rights", settings: rights)]
        }
        guard let wide = s.hostFrame(), let pad = s.open("window") else { return }
        let start = s.start(wide)
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
        guard let w = reset(), let left = s.engine.actions.preview("left-half", for: w, screens: screens),
            let right = s.engine.actions.preview("right-half", for: w, screens: screens)
        else {
            s.fail("the engine previews left-half and right-half", "no preview for window \(pad.id)")
            return
        }
        s.note("left half", left)
        s.note("right half", right)
        let key = GrabKey(key: "f7", modifiers: [.control, .option, .shift], tag: "")
        for (profile, want) in [("Halves", left), ("Rights", right), ("Halves", left)] {
            guard s.engine.actions.run(Profile.prefix + profile) else {
                s.fail("the engine switches to a saved profile", "\(profile) not applied")
                return
            }
            guard reset() != nil else { return }
            guard s.host.press(key) else {
                s.skip("host cannot press keys")
                return
            }
            let landed = s.host.wait(until: s.host.now + 1) { Contract.near(s.frame(pad.id), want) }
            s.note("\(profile) press", s.frame(pad.id))
            if !landed {
                s.fail(
                    "the chord runs the action \(profile) binds within 1 s, 1 point",
                    "want \(want), window \(Contract.show(s.frame(pad.id)))")
                return
            }
        }
    }
}
