import AppKit

import MooringsCore

// Sinking plays the quit animation over the menu bar icon: two black tentacles rise slowly from just
// under the menu bar beside the sailboat, then lash over the hull and drag it under, bubbles rise,
// and the scene fades. Nothing is drawn behind them, so they look to be on the screen itself.
// It runs once and then calls done.
@MainActor
final class Sinking {
    // width is the panel's width, wider than the status item so the tentacles have room.
    static let width: CGFloat = 80
    // below is how far the panel reaches under the menu bar.
    static let below: CGFloat = 18
    // grace is how long past the animation done runs anyway, should the timer stall.
    static let grace = 0.5

    // panel shows the scene, nil until play.
    private var panel: NSPanel?
    // timer redraws the scene while it plays.
    private var timer: Timer?
    // done runs once the scene ends, nil once it ran.
    private var done: (@MainActor () -> Void)?

    // play shows the scene over item, the status item's frame on screen, drawing the boat in the
    // appearance of the menu bar, then calls done.
    func play(over item: CGRect, appearance: NSAppearance, done: @escaping @MainActor () -> Void) {
        let h = item.height + Self.below
        let rect = CGRect(x: item.midX - Self.width / 2, y: item.maxY - h, width: Self.width, height: h)
        let p = NSPanel(
            contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = SinkingView(frame: CGRect(origin: .zero, size: rect.size), bar: item.height)
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
    static let tentacle = NSColor(white: 0.06, alpha: 1)
    // rim edges each tentacle so it shows against a dark menu bar.
    static let rim = NSColor(white: 1, alpha: 0.28)
    // sucker is the color of the suckers along each tentacle.
    static let sucker = NSColor(white: 0.42, alpha: 1)
    // icon is the size of the menu bar sailboat.
    static let icon: CGFloat = 18

    // pose is the frame to draw.
    var pose = Sink.pose(0)
    // bar is the menu bar's height, where the boat sits at rest.
    private let bar: CGFloat

    // init builds the view for a menu bar bar points tall.
    init(frame: CGRect, bar: CGFloat) {
        self.bar = bar
        super.init(frame: frame)
    }

    // init(coder:) is not used.
    required init?(coder: NSCoder) { nil }

    // isFlipped puts the origin at the top left.
    override var isFlipped: Bool { true }

    // draw paints the boat with the tentacles that hold it, and the bubbles. The boat fades below
    // its waterline as it goes under.
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width
        let h = bounds.height
        let rest = CGPoint(x: w / 2, y: bar / 2)
        let waterline = rest.y + 5
        ctx.setAlpha(pose.fade)

        let center = CGPoint(x: rest.x, y: rest.y + pose.depth * 22)
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
            let base = CGPoint(x: rest.x + side * 13, y: h - 1 + 30 * pose.depth)
            drawTentacle(from: base, to: hook, side: side, waterline: waterline)
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

    // drawTentacle draws one tentacle from base, under the menu bar, as far up as the pose's reach.
    // Free, it rises beside the boat and sways with its tip curled; as the pose grabs, the tip moves
    // to hook and curls over the gunwale. It is thick at the root and thin at the tip, with suckers
    // along the side that faces the boat.
    private func drawTentacle(from base: CGPoint, to hook: CGPoint, side: CGFloat, waterline: CGFloat) {
        guard pose.reach > 0 else { return }
        let bezier = { (p: [CGPoint], t: CGFloat) -> CGPoint in
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(
                x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x, y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
        }
        let mix = { (a: CGPoint, b: CGPoint, k: CGFloat) in CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
        let w = 2 * .pi * (1.2 * pose.flop + (side > 0 ? 0.35 : 0))
        let sway = sin(w) * min(1, pose.flop * 3)
        let tip = CGPoint(x: base.x + side * (7 + 4 * sway), y: waterline - 4 - 2 * cos(w * 1.3))
        let free = (
            rise: [
                base, CGPoint(x: base.x - side * (2 + 3 * cos(w)), y: base.y - 7),
                CGPoint(x: tip.x + side * 5 * sway, y: tip.y + 6), tip,
            ],
            curl: [tip, CGPoint(x: tip.x - side * (3 + 3 * sway), y: tip.y - 5), CGPoint(x: tip.x - side * 7, y: tip.y - 2),
                CGPoint(x: tip.x - side * 5, y: tip.y + 2)]
        )
        let held = CGPoint(x: hook.x + side * 2, y: hook.y - 2)
        let grip = (
            rise: [base, CGPoint(x: base.x + side * 4, y: base.y - 7), CGPoint(x: hook.x + side * 7, y: hook.y + 5), held],
            curl: [held, CGPoint(x: hook.x - side * 1, y: hook.y - 6), CGPoint(x: hook.x - side * 6, y: hook.y - 5),
                CGPoint(x: hook.x - side * 5, y: hook.y + 1)]
        )
        let k = CGFloat(pose.grab)
        let rise = zip(free.rise, grip.rise).map { mix($0, $1, k) }
        let curl = zip(free.curl, grip.curl).map { mix($0, $1, k) }
        let at = { (t: CGFloat) -> CGPoint in
            t < 0.78 ? bezier(rise, t / 0.78) : bezier(curl, (t - 0.78) / 0.22)
        }
        let width = { (t: CGFloat) -> CGFloat in 1 + 3.8 * (1 - t) * min(1, 0.5 + t * 3) }
        let steps = 40
        let shown = Int((CGFloat(steps) * pose.reach).rounded(.up))
        let alpha = 1 - 0.9 * pose.depth
        for (color, extra) in [(Self.rim, CGFloat(1.2)), (Self.tentacle, 0)] {
            for i in 0..<shown {
                let t = CGFloat(i) / CGFloat(steps)
                let seg = NSBezierPath()
                seg.move(to: at(t))
                seg.line(to: at(CGFloat(min(i + 1, shown)) / CGFloat(steps)))
                seg.lineWidth = width(t) + extra
                seg.lineCapStyle = .round
                color.withAlphaComponent(color.alphaComponent * min(1, 0.25 + t * 4) * alpha).setStroke()
                seg.stroke()
            }
        }
        Self.sucker.withAlphaComponent(alpha).setFill()
        for i in stride(from: 6, to: shown - 2, by: 3) {
            let t = CGFloat(i) / CGFloat(steps)
            let a = at(t), b = at(t + 0.01)
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.001)
            var n = CGPoint(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
            if n.x * side > 0 {
                n = CGPoint(x: -n.x, y: -n.y)
            }
            let r = 0.45 + 0.5 * (1 - t)
            let c = CGPoint(x: a.x + n.x * width(t) * 0.3, y: a.y + n.y * width(t) * 0.3)
            NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        }
    }
}
