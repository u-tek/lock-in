import SwiftUI
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

/// How far apart two colours look to someone with `vision` (OKLab distance after simulation).
func perceivedDistance(_ a: RGB, _ b: RGB, for vision: LKColorVision) -> Double {
    a.simulating(vision).distance(to: b.simulating(vision))
}
