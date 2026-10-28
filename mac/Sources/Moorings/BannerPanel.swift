import AppKit

import MooringsCore
import MooringsEngine

// BannerView is the banner's content. It holds the banner open while the pointer is over it and
// runs the banner's action on a click.
@MainActor
final class BannerView: NSView {
    // hover is told when the pointer enters or leaves.
    var hover: (Bool) -> Void = { _ in }
    // click is told about a click.
    var click: () -> Void = {}

    // updateTrackingAreas tracks the pointer over the whole banner.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    // mouseEntered holds the banner open.
    override func mouseEntered(with event: NSEvent) {
        hover(true)
    }

    // mouseExited lets the banner close again.
    override func mouseExited(with event: NSEvent) {
        hover(false)
    }

    // mouseDown runs the banner's action.
    override func mouseDown(with event: NSEvent) {
        click()
    }
}

// BannerPanel shows what moorings did in a box at the top right of the main display, in place
// of a system notification, and fades it away.
@MainActor
final class BannerPanel {
    // seconds is how long a banner stays up after it opens or the pointer leaves it.
    static let seconds = 5.0
    // fadeSeconds is how long a banner takes to fade away.
    static let fadeSeconds = 0.4

    // panel is the banner on screen, nil when none.
    private var panel: NSPanel?
    // timer closes the banner when it runs out.
    private var timer: Timer?

    // show replaces any banner with one titled title saying body, in palette's colors. A click runs
    // action, then closes the banner.
    func show(_ title: String, _ body: String, palette: Palette, action: (@MainActor () -> Void)? = nil) {
        close(fade: false)
        guard let main = NSScreen.screens.first else { return }
        let lines = Banner.wrap(body)
        let visible = main.visibleFrame
        let top = Frame(x: visible.minX, y: main.frame.height - visible.maxY, w: visible.width, h: visible.height)
        let box = Banner.frame(lines: lines.count, screen: top)
        let rect = NSRect(x: box.x, y: main.frame.height - box.y - box.h, width: box.w, height: box.h)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = BannerView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.backgroundColor = Self.color(palette.surface).cgColor
        view.layer?.borderColor = Self.color(palette.accent, alpha: 0.6).cgColor
        let mark = NSImageView(frame: NSRect(x: 12, y: rect.height - 32, width: 20, height: 20))
        mark.image = Mark.image(size: 20)
        mark.contentTintColor = Self.color(palette.accent)
        view.addSubview(mark)
        let head = NSTextField(labelWithString: title)
        head.font = .boldSystemFont(ofSize: 13)
        head.textColor = Self.color(palette.text)
        head.frame = NSRect(x: 40, y: rect.height - 30, width: rect.width - 52, height: 18)
        view.addSubview(head)
        let text = NSTextField(wrappingLabelWithString: lines.joined(separator: "\n"))
        text.font = .systemFont(ofSize: 12)
        text.textColor = Self.color(palette.text, alpha: 0.8)
        text.frame = NSRect(x: 40, y: 10, width: rect.width - 52, height: rect.height - 42)
        view.addSubview(text)
        view.hover = { [weak self] inside in
            if inside {
                self?.timer?.invalidate()
            } else {
                self?.arm()
            }
        }
        view.click = { [weak self] in
            action?()
            self?.close(fade: false)
        }
        p.contentView = view
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        arm()
    }

    // arm starts the countdown to closing.
    private func arm() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(fade: true) }
        }
    }

    // close removes the banner, fading it out when fade is true.
    func close(fade: Bool) {
        timer?.invalidate()
        timer = nil
        guard let p = panel else { return }
        panel = nil
        guard fade else {
            p.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeSeconds
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { p.orderOut(nil) }
        })
    }

    // color returns rgb as a color with alpha.
    static func color(_ rgb: RGB, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}

// MacNotifier is the Mac Notifier. It hands each message to send, which the app wires to its logged
// banner in the harbor palette.
@MainActor
final class MacNotifier: @preconcurrency Notifier {
    // send shows a title and a body.
    private let send: (String, String) -> Void

    // init shows messages through send.
    init(_ send: @escaping (String, String) -> Void) {
        self.send = send
    }

    // notify shows title and body.
    func notify(_ title: String, _ body: String) {
        send(title, body)
    }
}
