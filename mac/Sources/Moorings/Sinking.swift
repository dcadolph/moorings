import AppKit

import MooringsCore

// Sinking plays the quit animation over the menu bar icon: the water comes in, tentacles rise and
// pull the sailboat under, bubbles rise, and the scene fades. It runs once and then calls done.
@MainActor
final class Sinking {
    // width is the panel's width, wider than the status item so the tentacles have room.
    static let width: CGFloat = 64
    // below is how far the panel reaches under the menu bar.
    static let below: CGFloat = 48
    // grace is how long past the animation done runs anyway, should the timer stall.
    static let grace = 0.5

    // panel shows the scene, nil until play.
    private var panel: NSPanel?
    // timer redraws the scene while it plays.
    private var timer: Timer?
    // done runs once the scene ends, nil once it ran.
    private var done: (@MainActor () -> Void)?

    // play shows the scene over item, the status item's frame on screen, drawing the boat in the
    // appearance of the menu bar and the water in accent, then calls done.
    func play(over item: CGRect, appearance: NSAppearance, accent: NSColor, done: @escaping @MainActor () -> Void) {
        let h = item.height + Self.below
        let rect = CGRect(x: item.midX - Self.width / 2, y: item.maxY - h, width: Self.width, height: h)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = SinkingView(frame: CGRect(origin: .zero, size: rect.size), bar: item.height, accent: accent)
        view.appearance = appearance
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
        self.done = done
        let start = AppDelegate.now
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                let elapsed = (AppDelegate.now - start) / Sink.seconds
                view.pose = Sink.pose(elapsed)
                view.needsDisplay = true
                if elapsed >= 1 {
                    self?.finish()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + Sink.seconds + Self.grace) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    // finish stops the scene and runs done, once.
    private func finish() {
        guard let done else { return }
        self.done = nil
        timer?.invalidate()
        panel?.orderOut(nil)
        done()
    }
}

// SinkingView draws one pose of the quit animation, top-left origin.
final class SinkingView: NSView {
    // tentacle is the octopus's color.
    static let tentacle = NSColor(srgbRed: 0.78, green: 0.32, blue: 0.55, alpha: 1)
    // icon is the size of the menu bar sailboat.
    static let icon: CGFloat = 18

    // pose is the frame to draw.
    var pose = Sink.pose(0)
    // bar is the menu bar's height, where the boat sits at rest.
    private let bar: CGFloat
    // accent colors the water.
    private let accent: NSColor

    // init builds the view for a menu bar bar points tall and water in accent.
    init(frame: CGRect, bar: CGFloat, accent: NSColor) {
        self.bar = bar
        self.accent = accent
        super.init(frame: frame)
    }

    // init(coder:) is not used.
    required init?(coder: NSCoder) { nil }

    // isFlipped puts the origin at the top left.
    override var isFlipped: Bool { true }

    // draw paints the water, the boat with the tentacles that hold it, and the bubbles.
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height
        let rest = CGPoint(x: w / 2, y: bar / 2)
        let waterline = rest.y + 5
        ctx.setAlpha(pose.fade)

        let pool = NSBezierPath(ovalIn: CGRect(x: 2, y: waterline - (h - waterline), width: w - 4, height: 2 * (h - waterline)))
        NSGraphicsContext.saveGraphicsState()
        let surface = NSBezierPath()
        let phase = (pose.reach + pose.depth + pose.bubbles) * 5
        surface.move(to: CGPoint(x: 0, y: h))
        for x in stride(from: 0.0, through: w, by: 2) {
            surface.line(to: CGPoint(x: x, y: waterline - 1 + 1.3 * sin(x * 0.3 + phase)))
        }
        surface.line(to: CGPoint(x: w, y: h))
        surface.close()
        surface.addClip()
        pool.addClip()
        NSGradient(starting: accent.withAlphaComponent(0.5 * pose.water), ending: accent.withAlphaComponent(0))?
            .draw(in: CGRect(x: 0, y: waterline, width: w, height: h - waterline), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        let center = CGPoint(x: rest.x, y: rest.y + pose.depth * (h - 18 - rest.y))
        var turn = AffineTransform(translationByX: center.x, byY: center.y)
        turn.rotate(byDegrees: pose.tilt)
        turn.translate(x: -Self.icon / 2, y: -Self.icon / 2)
        let boat = Mark.path(in: CGRect(x: 0, y: 0, width: Self.icon, height: Self.icon))
        boat.transform(using: turn)
        let ink = NSColor.labelColor
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: w, height: waterline)).addClip()
        ink.setFill()
        boat.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 0, y: waterline, width: w, height: h - waterline)).addClip()
        ink.withAlphaComponent(0.35 * (1 - pose.depth)).setFill()
        boat.fill()
        NSGraphicsContext.restoreGraphicsState()

        let scale = Self.icon / Mark.box.width
        let gunwale = { (x: CGFloat) -> CGPoint in
            turn.transform(CGPoint(x: (x - Mark.box.minX) * scale, y: (39.75 - Mark.box.minY) * scale))
        }
        for (side, hook) in [(-1.0, gunwale(13)), (1.0, gunwale(45))] {
            let base = CGPoint(x: rest.x + side * 13, y: h - 8)
            drawTentacle(from: base, to: hook, side: side)
        }

        if pose.bubbles > 0 {
            for (i, dx) in [-4.0, 3.0, -1.0].enumerated() {
                let b = min(max(pose.bubbles * 1.6 - Double(i) * 0.3, 0), 1)
                guard b > 0, b < 1 else { continue }
                let y = h - 8 - b * (h - 8 - waterline + 2)
                let r = 1.2 + Double(i) * 0.5
                ink.withAlphaComponent(0.5 * (1 - b)).setStroke()
                let bubble = NSBezierPath(ovalIn: CGRect(x: rest.x + dx - r, y: y - r, width: 2 * r, height: 2 * r))
                bubble.lineWidth = 0.8
                bubble.stroke()
            }
        }
    }

    // drawTentacle draws one tentacle from base, under the water, up past the hull on its outer side
    // and curled over the gunwale at hook, as far as the pose's reach. It thickens from a faint root in
    // the water to its widest below the hull, then thins to the curled tip.
    private func drawTentacle(from base: CGPoint, to hook: CGPoint, side: CGFloat) {
        guard pose.reach > 0 else { return }
        let bezier = { (p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat) -> CGPoint in
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
        }
        let rise = (base, CGPoint(x: base.x + side * 4, y: base.y - 14), CGPoint(x: hook.x + side * 7, y: hook.y + 8),
                    CGPoint(x: hook.x + side * 2, y: hook.y - 2))
        let curl = (rise.3, CGPoint(x: hook.x - side * 1, y: hook.y - 6), CGPoint(x: hook.x - side * 6, y: hook.y - 5),
                    CGPoint(x: hook.x - side * 5, y: hook.y + 1))
        let at = { (t: CGFloat) -> CGPoint in
            t < 0.75 ? bezier(rise.0, rise.1, rise.2, rise.3, t / 0.75)
                : bezier(curl.0, curl.1, curl.2, curl.3, (t - 0.75) / 0.25)
        }
        let steps = 32
        let shown = Int((CGFloat(steps) * pose.reach).rounded(.up))
        for i in 0..<shown {
            let t = CGFloat(i) / CGFloat(steps)
            let seg = NSBezierPath()
            seg.move(to: at(t))
            seg.line(to: at(CGFloat(min(i + 1, shown)) / CGFloat(steps)))
            seg.lineWidth = 1 + 3.6 * sin(.pi * min(1, t * 1.6 + 0.15)) * (1 - t * 0.7)
            seg.lineCapStyle = .round
            Self.tentacle.withAlphaComponent(min(1, 0.2 + t * 4) * (1 - 0.75 * pose.depth)).setStroke()
            seg.stroke()
        }
    }
}
