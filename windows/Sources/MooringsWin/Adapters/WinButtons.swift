import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// WinButtons turns presses of the extra mouse buttons and clicks on a window's caption buttons into the
// actions bound to them. The hook asks takes from its callback, which can arrive while a pass waits on
// another process's window, so takes only reads and queues, and the action runs from the message loop.
final class WinButtons {
    // Bound is an action a press asked for.
    private struct Bound {
        // name is the action to run.
        var name: String
        // window is the window under a caption button click, nil for the focused window.
        var window: WindowID?
        // masks is true when Alt or the Windows key is held, whose release must not reach the shell.
        var masks: Bool
        // tick is when the press came, by GetTickCount64.
        var tick: UInt64
    }

    // message is the private thread message that runs the queue. The tray's WM_APP + 3 goes to its
    // window, so the two never meet.
    static let message = UINT(WM_APP) + 3
    // staleMillis is how old a queued action may be and still run. Windows drops thread messages during
    // a modal menu loop, and an action that waited through one would fire long after its press.
    static let staleMillis: UInt64 = 2000

    // app holds the choices, the engine and the shortcuts' state.
    private unowned let app: App
    // queued holds the actions waiting for the message loop, oldest first.
    private var queued: [Bound] = []

    // init builds the buttons for app.
    init(app: App) {
        self.app = app
    }

    // takes reports whether a press of the numbered button at p is bound to an action, and queues the
    // action if so. Unbound presses, and every press while paused or while an ignored app is in front,
    // pass on, as does a binding this platform cannot run.
    func takes(_ number: Int, at p: POINT) -> Bool {
        let choices = app.engine.anchors.choices
        guard !choices.paused, app.hotkeys.enabled else { return false }
        let press = number == WinMouseHook.left ? click(at: p, choices) : extra(number, choices)
        guard let press, app.engine.actions.supports(press.name) else { return false }
        queued.append(press)
        _ = PostThreadMessageW(GetCurrentThreadId(), Self.message, 0, 0)
        return true
    }

    // extra returns the action bound to a mouse button other than the left one.
    private func extra(_ number: Int, _ choices: Choices) -> Bound? {
        guard !choices.mouseButtons.isEmpty else { return nil }
        let sizes = Set(Bindings(choices).sizes.map(\.name))
        guard let name = MouseButtons.valid(choices.mouseButtons, sizes: sizes).map[number] else { return nil }
        return Bound(name: name, window: nil, masks: false, tick: GetTickCount64())
    }

    // click returns the action bound to a left press at p, nil unless the press lands on a caption button
    // with the modifiers a binding takes. The window is asked only when one does, so a press with no
    // binding sends no message. Any answer but the three buttons passes, so a window that draws its own
    // caption and answers as client keeps its native clicks.
    private func click(at p: POINT, _ choices: Choices) -> Bound? {
        guard !choices.buttonClicks.isEmpty else { return nil }
        let held = Modifiers.now()
        guard
            let modifier = ButtonClicks.modifier(
                shift: held.contains(.shift), option: held.contains(.option),
                command: held.contains(.command), control: held.contains(.control)),
            ButtonClicks.bound(choices.buttonClicks, modifier: modifier),
            let root = WindowFromPoint(p).flatMap({ GetAncestor($0, WinWatcher.root) }),
            let answer = WinDrag.hit(root, at: p), let button = Self.button(answer),
            let name = ButtonClicks.action(
                choices.buttonClicks, button, modifier, sizes: Set(Bindings(choices).sizes.map(\.name)))
        else { return nil }
        let masks = held.contains(.option) || held.contains(.command)
        return Bound(name: name, window: WinWindows.id(root), masks: masks, tick: GetTickCount64())
    }

    // button names the caption button of a WM_NCHITTEST answer: HTCLOSE, HTMINBUTTON or HTMAXBUTTON.
    static func button(_ answer: DWORD_PTR) -> WindowButton? {
        switch answer {
        case 20: .red
        case 8: .yellow
        case 9: .green
        default: nil
        }
    }

    // deliver runs the queue when msg is the buttons' message and reports whether it was. A press that
    // waited too long is dropped.
    func deliver(_ msg: MSG) -> Bool {
        guard msg.message == Self.message, msg.hwnd == nil else { return false }
        let now = GetTickCount64()
        let due = queued
        queued = []
        for press in due where now &- press.tick <= Self.staleMillis {
            if press.masks {
                WinDrag.maskKeys()
            }
            app.engine.actions.run(press.name, window: press.window)
        }
        return true
    }
}
