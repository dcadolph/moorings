import Foundation

// Banner holds the pure math of the moorings banner: how its text wraps, which style it draws in,
// and where its box sits on a screen.
public enum Banner {
    // Style is the banner's color style, following the macOS appearance.
    public enum Style: String, Sendable {
        case light, dark
    }

    // width is the box width in points.
    public static let width = 380.0
    // marginX is the distance from the screen's right edge in points.
    public static let marginX = 14.0
    // marginY is the distance from the screen's top edge in points.
    public static let marginY = 10.0
    // wrapAt is the most characters a body line holds before it wraps.
    public static let wrapAt = 46

    // wrap splits text into lines of at most wrapAt characters at spaces, keeping its newlines. A
    // word longer than a line stays whole on a line of its own.
    public static func wrap(_ text: String) -> [String] {
        var lines: [String] = []
        for para in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in para.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                if line.isEmpty {
                    line = String(word)
                } else if line.count + 1 + word.count <= wrapAt {
                    line += " " + word
                } else {
                    lines.append(line)
                    line = String(word)
                }
            }
            lines.append(line)
        }
        return lines
    }

    // style returns dark when the macOS interface style is "Dark" and light otherwise.
    public static func style(interfaceStyle: String?) -> Style {
        interfaceStyle == "Dark" ? .dark : .light
    }

    // frame returns the box for a banner with lines body lines on a screen whose usable frame is
    // screen.
    public static func frame(lines: Int, screen: Frame) -> Frame {
        Frame(
            x: screen.x + screen.w - width - marginX,
            y: screen.y + marginY,
            w: width,
            h: Double(42 + 16 * lines)
        )
    }
}
