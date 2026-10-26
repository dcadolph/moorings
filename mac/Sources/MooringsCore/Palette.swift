import Foundation

// RGB is an sRGB color with components from 0 to 1.
public struct RGB: Sendable, Equatable {
    // red is the red component.
    public var red: Double
    // green is the green component.
    public var green: Double
    // blue is the blue component.
    public var blue: Double

    // black and white are the fallback label colors on an accent fill.
    public static let black = RGB(red: 0, green: 0, blue: 0)
    public static let white = RGB(red: 1, green: 1, blue: 1)

    // init creates a color from components.
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    // init parses a #rrggbb hex string, or returns nil when it is not one.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xff) / 255
        green = Double((value >> 8) & 0xff) / 255
        blue = Double(value & 0xff) / 255
    }

    // luminance is the WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    // contrast is the WCAG contrast ratio between this color and other, from 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// Tint is a color with an opacity from 0 to 1.
public struct Tint: Sendable, Equatable {
    // color is the color.
    public var color: RGB
    // alpha is the opacity.
    public var alpha: Double
}

// Palette is the set of colors moorings draws its banners, footprint and panels in.
public struct Palette: Sendable, Equatable {
    // background is behind the whole surface.
    public var background: RGB
    // surface is behind cards and banners.
    public var surface: RGB
    // text is the main text color.
    public var text: RGB
    // muted is the color for hints and secondary lines.
    public var muted: RGB
    // accent fills buttons and draws rings.
    public var accent: RGB

    // textMinimum is the WCAG AA contrast for normal text.
    public static let textMinimum = 4.5
    // accentMinimum is the WCAG AA contrast for graphics and large text.
    public static let accentMinimum = 3.0
    // footprintFillAlpha is the opacity of the footprint fill.
    public static let footprintFillAlpha = 0.20
    // footprintStrokeAlpha is the opacity of the footprint stroke.
    public static let footprintStrokeAlpha = 0.70

    // onAccent is the label color on an accent fill: the background when it passes, else black or
    // white, whichever contrasts more.
    public var onAccent: RGB {
        if background.contrast(with: accent) >= Self.textMinimum {
            return background
        }
        return RGB.white.contrast(with: accent) >= RGB.black.contrast(with: accent) ? .white : .black
    }

    // accentText is the accent when it passes as small text on the background, else the text color.
    public var accentText: RGB {
        accent.contrast(with: background) >= Self.textMinimum ? accent : text
    }

    // footprintFill is the accent at 20% opacity, drawn inside the snap footprint.
    public var footprintFill: Tint { Tint(color: accent, alpha: Self.footprintFillAlpha) }

    // footprintStroke is the accent at 70% opacity, drawn around the snap footprint.
    public var footprintStroke: Tint { Tint(color: accent, alpha: Self.footprintStrokeAlpha) }

    // harbor is the one palette moorings uses: near-black surfaces, white text and a cream accent.
    public static let harbor = Palette(background: RGB(hex: "#0f1012")!, surface: RGB(hex: "#0f1012")!,
                                       text: RGB(hex: "#ffffff")!, muted: RGB(hex: "#aaa59b")!,
                                       accent: RGB(hex: "#f3e3b8")!)
}
