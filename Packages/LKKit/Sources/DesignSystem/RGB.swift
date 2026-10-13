import Foundation

/// A colour in sRGB, components 0...1 (gamma-encoded, as designers write them).
///
/// Tokens are numbers rather than `Color`s so the tests can check contrast and how far apart
/// colours look with plain arithmetic. `Color(rgb:)` turns one into something to draw.
public struct RGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The nearest `0xRRGGBB`.
    public var hex: UInt32 {
        (Self.byte(red) << 16) | (Self.byte(green) << 8) | Self.byte(blue)
    }

    /// "#RRGGBB", for labels in the design lab.
    public var hexString: String {
        String(format: "#%06X", hex)
    }

    // MARK: - Contrast (WCAG 2.x)

    /// Relative luminance as WCAG defines it: 0 for black, 1 for white.
    public var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// The WCAG contrast ratio between this colour and `other`, from 1 (none) to 21 (black on
    /// white). Order doesn't matter. Body text needs 4.5; large text and shapes that carry meaning
    /// need 3.
    public func contrastRatio(with other: RGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour at `opacity` laid over `background`: what a translucent fill looks like on
    /// screen. Blends the encoded components, as Core Graphics does for sRGB.
    public func composited(over background: RGB, opacity: Double) -> RGB {
        let t = min(max(opacity, 0), 1)
        return RGB(
            red: red * t + background.red * (1 - t),
            green: green * t + background.green * (1 - t),
            blue: blue * t + background.blue * (1 - t)
        )
    }

    // MARK: - Perception

    /// How different two colours look: the straight-line distance between them in OKLab. About
    /// 0.02 is the smallest difference most people notice side by side; colours that must be told
    /// apart at a glance, at 20 points in the island, need several times that.
    public func distance(to other: RGB) -> Double {
        let a = OKLab(self), b = OKLab(other)
        let dl = a.l - b.l, da = a.a - b.a, db = a.b - b.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// How this colour looks to someone with a colour-vision deficiency, at full severity
    /// (Machado, Oliveira and Fernandes, 2009).
    public func simulating(_ vision: LKColorVision) -> RGB {
        guard let m = vision.matrix else { return self }
        let r = Self.linear(red), g = Self.linear(green), b = Self.linear(blue)
        return RGB(
            red: Self.encoded(m[0] * r + m[1] * g + m[2] * b),
            green: Self.encoded(m[3] * r + m[4] * g + m[5] * b),
            blue: Self.encoded(m[6] * r + m[7] * g + m[8] * b)
        )
    }

    // MARK: - Transfer

    /// sRGB's transfer function: encoded component to linear light.
    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Linear light back to an encoded component, clamped into gamut.
    static func encoded(_ c: Double) -> Double {
        let clamped = min(max(c, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    private static func byte(_ c: Double) -> UInt32 {
        UInt32((min(max(c, 0), 1) * 255).rounded())
    }
}

/// Ways of seeing colour, for checking that tokens which carry meaning stay apart for everyone.
/// Roughly 1 in 12 men and 1 in 200 women have some red–green deficiency; a squad of six
/// teenagers will often include one.
public enum LKColorVision: String, CaseIterable, Sendable {
    case typical
    /// No long-wavelength (red) cones.
    case protanopia
    /// No medium-wavelength (green) cones: the most common.
    case deuteranopia
    /// No short-wavelength (blue) cones: rare.
    case tritanopia

    /// Machado et al.'s severity-1.0 matrix, row-major, applied to linear RGB.
    var matrix: [Double]? {
        switch self {
        case .typical:
            return nil
        case .protanopia:
            return [0.152286, 1.052583, -0.204868,
                    0.114503, 0.786281, 0.099216,
                    -0.003882, -0.048116, 1.051998]
        case .deuteranopia:
            return [0.367322, 0.860646, -0.227968,
                    0.280085, 0.672501, 0.047413,
                    -0.011820, 0.042940, 0.968881]
        case .tritanopia:
            return [1.255528, -0.076749, -0.178779,
                    -0.078411, 0.930809, 0.147602,
                    0.004733, 0.691367, 0.303900]
        }
    }
}

/// OKLab (Björn Ottosson, 2020): a perceptual colour space, where equal distances look like
/// roughly equal differences. `l` is lightness 0...1; `a` and `b` are the green–red and
/// blue–yellow axes.
struct OKLab: Hashable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    /// How colourful it is; near 0 for greys.
    var chroma: Double {
        (a * a + b * b).squareRoot()
    }

    init(_ rgb: RGB) {
        let r = RGB.linear(rgb.red), g = RGB.linear(rgb.green), bl = RGB.linear(rgb.blue)
        let lms0 = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl
        let lms1 = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl
        let lms2 = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl
        let l_ = cbrt(lms0), m_ = cbrt(lms1), s_ = cbrt(lms2)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }
}
