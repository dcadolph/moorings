import AppKit

// Mark draws the moorings sailboat: a mast, two sails, and a hull.
enum Mark {
    // box is the drawing's square in its own units, top-left origin.
    static let box = CGRect(x: 8.4, y: 9.5, width: 43, height: 43)

    // path returns the mark scaled into rect, in a flipped (top-left) context.
    static func path(in rect: CGRect) -> NSBezierPath {
        let s = min(rect.width, rect.height) / box.width
        let ox = rect.midX - box.width * s / 2 - box.minX * s
        let oy = rect.midY - box.height * s / 2 - box.minY * s
        let p = { (x: CGFloat, y: CGFloat) in NSPoint(x: ox + x * s, y: oy + y * s) }
        let out = NSBezierPath()
        let mast = CGRect(x: ox + 29.2 * s, y: oy + 10.75 * s, width: 3.1 * s, height: 29 * s)
        out.append(NSBezierPath(roundedRect: mast, xRadius: 1.55 * s, yRadius: 1.55 * s))
        out.move(to: p(26, 14.25))
        out.line(to: p(26, 36.2))
        out.line(to: p(11.4, 36.2))
        out.close()
        out.move(to: p(35.4, 19))
        out.line(to: p(35.4, 36.2))
        out.line(to: p(48.4, 36.2))
        out.close()
        out.move(to: p(11.6, 39.75))
        out.line(to: p(46.6, 39.75))
        out.line(to: p(40.6, 50.4))
        out.curve(to: p(39, 51.25), controlPoint1: p(40.1, 51.25), controlPoint2: p(40.1, 51.25))
        out.line(to: p(19.3, 51.25))
        out.curve(to: p(17.7, 50.4), controlPoint1: p(18.2, 51.25), controlPoint2: p(18.2, 51.25))
        out.close()
        return out
    }

    // image returns the mark at size points as a template image, so it follows the menu bar.
    static func image(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            NSColor.black.setFill()
            path(in: rect).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Moorings"
        return img
    }
}
