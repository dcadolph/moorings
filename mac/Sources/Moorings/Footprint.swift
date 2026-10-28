import AppKit

import MooringsCore
import MooringsEngine

// Footprint is the borderless panel that shows where a dragged window will land.
@MainActor
final class Footprint {
    // panel is the footprint window, nil while hidden.
    private var panel: NSPanel?

    // fadeTime is how long the shown footprint takes to fade out.
    private var fadeTime = 0.0
    // shown is the frame the footprint covers, nil while hidden.
    private(set) var shown: Frame?
    // haptic reports whether a show taps the trackpad when the style asks, as the drag's footprint
    // does and the throw's does not.
    private let haptic: Bool

    // init builds a hidden footprint that taps the trackpad on a show when haptic is set.
    init(haptic: Bool = false) {
        self.haptic = haptic
    }

    // show draws the footprint at frame, in global top-left coordinates, in style's colors on palette, fading
    // it in when style fades, and taps the trackpad when this footprint and the style both ask.
    func show(_ frame: Frame, palette: Palette, style: FootprintStyle) {
        if haptic, style.haptic {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.x, y: primary - frame.y - frame.h, width: frame.w, height: frame.h)
        fadeTime = style.fadeTime
        shown = frame
        if let panel {
            Self.paint(panel.contentView, palette: palette, style: style)
            if fadeTime > 0 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = fadeTime
                    panel.animator().setFrame(rect, display: true)
                }
            } else {
                panel.setFrame(rect, display: true)
            }
            return
        }
        let p = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        Self.paint(view, palette: palette, style: style)
        p.contentView = view
        panel = p
        guard fadeTime > 0 else {
            p.orderFrontRegardless()
            return
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeTime
            p.animator().alphaValue = 1
        }
    }

    // hide removes the footprint, fading it out when it faded in.
    func hide() {
        shown = nil
        guard let p = panel else { return }
        panel = nil
        guard fadeTime > 0 else {
            p.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = fadeTime
                p.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { p.orderOut(nil) } })
    }

    // paint colors view's layer from style on palette.
    private static func paint(_ view: NSView?, palette: Palette, style: FootprintStyle) {
        let (fill, stroke) = style.tints(palette)
        view?.layer?.borderWidth = max(0, style.borderWidth)
        view?.layer?.backgroundColor = color(fill).cgColor
        view?.layer?.borderColor = color(stroke).cgColor
    }

    // color returns tint as a color.
    static func color(_ tint: Tint) -> NSColor {
        NSColor(srgbRed: tint.color.red, green: tint.color.green, blue: tint.color.blue, alpha: tint.alpha)
    }
}

// Footprint is the Mac OverlayView.
extension Footprint: @preconcurrency OverlayView {
    // show draws the footprint at frame in style's colors on palette.
    func show(_ frame: Frame, style: FootprintStyle, palette: Palette) {
        show(frame, palette: palette, style: style)
    }
}

// MacDrag feeds the event tap's drag to the engine's DragFollower one main queue turn after each
// event, so the tap never waits on a window read.
@MainActor
final class MacDrag {
    // follower is the engine's drag follower.
    let follower: DragFollower

    // init takes the engine's follower from app and gives it the Mac's snap panel.
    init(app: AppDelegate) {
        follower = app.engine.drag
        follower.panel = MacDragPanel(app: app)
    }

    // pressed starts following a new drag from p.
    func pressed(_ p: CGPoint) {
        DispatchQueue.main.async { [weak self] in self?.follower.began(at: Point(x: p.x, y: p.y)) }
    }

    // dragged follows the cursor at p with flags down.
    func dragged(_ p: CGPoint, flags: CGEventFlags) {
        let held = Modifiers(flags: flags)
        DispatchQueue.main.async { [weak self] in self?.follower.moved(Point(x: p.x, y: p.y), held: held) }
    }

    // released drops the window where the drag ended.
    func released() {
        DispatchQueue.main.async { [weak self] in self?.follower.ended(held: []) }
    }
}

// MacDragPanel is the snap panel during a drag: once the cursor pauses it shows a row of targets
// above the cursor, and the target under the cursor picks the drop.
@MainActor
final class MacDragPanel: @preconcurrency DragPanelHook {
    // app is the running app delegate.
    private unowned let app: AppDelegate
    // panel shows the snap panel's targets.
    private let panel = SnapPanelWindow()
    // cells are the snap panel's target frames while it shows, nil while it is hidden.
    private var cells: [Frame]?
    // dwell fires once the cursor has paused during a drag.
    private var dwell: Timer?
    // dwellFrom is where the cursor was when the current pause began.
    private var dwellFrom: CGPoint?
    // drag counts drags, so a pause timer from an earlier drag shows nothing.
    private var drag = 0

    // init builds the panel for app.
    init(app: AppDelegate) {
        self.app = app
    }

    // zone highlights the target under p when the panel is on for w with held, waits for a pause to
    // show the panel, and returns the target's action.
    func zone(at p: Point, window w: WindowInfo, held: Modifiers, option: Bool) -> String? {
        let s = app.engine.anchors.choices.snapping
        let on =
            s.snapPanel && !option && !app.engine.anchors.pinned(w) && !app.engine.anchors.isCastOff(w.id)
            && Modifiers(names: s.snapModifiers).map(held.isSuperset) == true
        let hit = on ? cells.flatMap { SnapPanel.hit(SnapPoint(p.x, p.y), $0) } : nil
        panel.highlight(hit)
        if on {
            wait(CGPoint(x: p.x, y: p.y))
        }
        guard let hit, hit < s.panelActions.count else { return nil }
        return s.panelActions[hit]
    }

    // reset hides the panel and forgets the pause.
    func reset() {
        drag += 1
        dwell?.invalidate()
        dwell = nil
        dwellFrom = nil
        cells = nil
        panel.hide()
    }

    // wait restarts the pause before the snap panel shows whenever the cursor at p has moved more than
    // SnapPanel.still since the pause began. Once the panel shows it stays until the drag ends.
    private func wait(_ p: CGPoint) {
        guard cells == nil else { return }
        if let from = dwellFrom, abs(p.x - from.x) <= SnapPanel.still, abs(p.y - from.y) <= SnapPanel.still {
            return
        }
        dwellFrom = p
        dwell?.invalidate()
        let this = drag
        dwell = Timer.scheduledTimer(withTimeInterval: SnapPanel.dwellSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.drag == this else { return }
                self.show()
            }
        }
    }

    // show shows the snap panel over the paused cursor, on the display under it.
    private func show() {
        guard let p = dwellFrom, cells == nil else { return }
        let screens = Screens.current()
        guard
            let f = screens.full.first(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h })
        else { return }
        let names = app.engine.anchors.choices.snapping.panelActions
        guard !names.isEmpty else { return }
        let layout = SnapPanel.layout(names.count, at: SnapPoint(p.x, p.y), screen: f)
        cells = layout.cells
        panel.show(layout.panel, cells: layout.cells, names: names, palette: .harbor)
    }
}

// BadgePanel is the Mac BadgeView: the small count that sits on the top-right corner of a stacked
// window while the pointer rests at that window's top-left corner.
@MainActor
final class BadgePanel {
    // panel is the badge window, nil until first shown.
    private var panel: NSPanel?
    // label draws the count.
    private let label = NSTextField(labelWithString: "")
    // shown is the mark the badge paints, nil when hidden.
    private(set) var shown: BadgeMark?

    // show draws count at the top-right corner of front.
    func show(_ count: Int, at front: Frame, palette: Palette) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let size = NSSize(width: 30, height: 22)
        let rect = NSRect(
            x: front.x + front.w - size.width - 8, y: primary - front.y - size.height - 8,
            width: size.width, height: size.height)
        let p = panel ?? makePanel(rect)
        panel = p
        p.contentView?.layer?.backgroundColor = BannerPanel.color(palette.accent).cgColor
        label.textColor = BannerPanel.color(palette.onAccent)
        label.stringValue = "\(count)"
        p.setFrame(rect, display: true)
        p.orderFrontRegardless()
        shown = BadgeMark(count: count, front: front)
    }

    // hide removes the badge.
    func hide() {
        panel?.orderOut(nil)
        shown = nil
    }

    // makePanel builds the badge window at rect.
    private func makePanel(_ rect: NSRect) -> NSPanel {
        let p = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = rect.height / 2
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: (rect.height - 16) / 2, width: rect.width, height: 16)
        label.autoresizingMask = [.width]
        view.addSubview(label)
        p.contentView = view
        return p
    }
}

// BadgePanel is the Mac BadgeView.
extension BadgePanel: @preconcurrency BadgeView {}

// SnapPanelWindow is the row of targets that appears near the cursor when a drag pauses. Each target
// draws where its action puts a window.
@MainActor
final class SnapPanelWindow {
    // panel is the panel window, nil while hidden.
    private var panel: NSPanel?
    // view draws the targets.
    private let view = SnapPanelView()

    // show draws the targets for names at cells inside frame, all in global top-left coordinates.
    func show(_ frame: Frame, cells: [Frame], names: [String], palette: Palette) {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let rect = NSRect(x: frame.x, y: primary - frame.y - frame.h, width: frame.w, height: frame.h)
        view.cells = cells.map {
            NSRect(x: $0.x - frame.x, y: frame.y + frame.h - $0.y - $0.h, width: $0.w, height: $0.h)
        }
        view.names = names
        view.lit = nil
        view.background = BannerPanel.color(palette.surface)
        view.ink = BannerPanel.color(palette.muted)
        view.accent = BannerPanel.color(palette.accent)
        view.needsDisplay = true
        let p = panel ?? makePanel(rect)
        panel = p
        p.setFrame(rect, display: true)
        p.orderFrontRegardless()
    }

    // highlight lights the target at index i, or none when nil.
    func highlight(_ i: Int?) {
        guard panel != nil, view.lit != i else { return }
        view.lit = i
        view.needsDisplay = true
    }

    // hide removes the panel.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // makePanel builds the panel window at rect.
    private func makePanel(_ rect: NSRect) -> NSPanel {
        let p = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        view.frame = NSRect(origin: .zero, size: rect.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        return p
    }
}

// SnapPanelView draws the snap panel: a rounded card with one target per action, each showing the
// part of a screen its action fills.
final class SnapPanelView: NSView {
    // cells lists each target's rect.
    var cells: [NSRect] = []
    // names lists each target's action.
    var names: [String] = []
    // lit is the index of the target under the cursor, nil when none is.
    var lit: Int?
    // background fills the card.
    var background = NSColor.windowBackgroundColor
    // ink draws the targets.
    var ink = NSColor.secondaryLabelColor
    // accent draws the lit target.
    var accent = NSColor.controlAccentColor

    // draw paints the card and each target with a miniature of where its action puts a window.
    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        for (i, c) in cells.enumerated() where i < names.count {
            let color = i == lit ? accent : ink
            let screen = c.insetBy(dx: 4, dy: 4)
            color.setStroke()
            let outline = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1
            outline.stroke()
            let area = Frame(x: 0, y: 0, w: screen.width, h: screen.height)
            guard let f = Geometry.position(names[i], area) else {
                let label = Keymaps.label(names[i]) as NSString
                label.draw(
                    in: screen.insetBy(dx: 2, dy: 2),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: color])
                continue
            }
            color.withAlphaComponent(i == lit ? 0.9 : 0.5).setFill()
            let r = NSRect(x: screen.minX + f.x, y: screen.maxY - f.y - f.h, width: f.w, height: f.h).insetBy(
                dx: 1.5, dy: 1.5)
            NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
        }
    }
}
