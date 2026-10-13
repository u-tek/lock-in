import SwiftUI
import UIKit
@testable import DesignSystem

/// Both appearances, for checks that must hold in each.
var appearances: [ColorScheme] { [.light, .dark] }

/// Every unordered pair, each once.
func pairs<T>(_ items: [T]) -> [(T, T)] {
    var result: [(T, T)] = []
    for i in items.indices {
        for j in items.indices where j > i {
            result.append((items[i], items[j]))
        }
    }
    return result
}

/// A UIKit colour in one appearance, resolved the same way `LKColorToken.resolved(in:)` does.
func resolve(_ color: UIColor, in scheme: ColorScheme) -> UIColor {
    color.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
}

/// Red, green, blue and alpha in extended sRGB.
func components(_ color: UIColor) -> (red: Double, green: Double, blue: Double, alpha: Double) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    _ = color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (Double(red), Double(green), Double(blue), Double(alpha))
}

/// Straight-line distance between two resolved colours in sRGB, alpha included: 0 for the same
/// colour, about 1.7 for black and white. A rough measure, but the system colours that have to be
/// told apart are far apart on it.
func distance(_ a: UIColor, _ b: UIColor) -> Double {
    let x = components(a), y = components(b)
    let dr = x.red - y.red, dg = x.green - y.green, db = x.blue - y.blue, da = x.alpha - y.alpha
    return (dr * dr + dg * dg + db * db + da * da).squareRoot()
}

/// Relative luminance as WCAG defines it (0 black, 1 white), ignoring alpha.
func luminance(_ color: UIColor) -> Double {
    let c = components(color)
    func linear(_ v: Double) -> Double {
        let v = min(max(v, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
}
