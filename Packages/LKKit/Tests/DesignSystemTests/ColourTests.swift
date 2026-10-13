import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// Every colour is a system colour (design/SYSTEM.md). The values are Apple's, so these check
/// that each name points at the right one, and that the ones views lean on behave as expected in
/// both appearances.
@Suite struct ColourTests {
    @Test func tintIsSystemIndigo() {
        #expect(LKColorCatalogue.tint.uiKitName == "systemIndigo")
        for scheme in appearances {
            let tint = LKColorCatalogue.tint.resolved(in: scheme)
            #expect(distance(tint, resolve(.systemIndigo, in: scheme)) < 0.001, "\(scheme)")
        }
    }

    @Test func tokensAreTheSystemColoursTheyName() {
        let expected: [(LKColorToken, UIColor)] = [
            (LKColorCatalogue.groupedBackground, .systemGroupedBackground),
            (LKColorCatalogue.secondaryGroupedBackground, .secondarySystemGroupedBackground),
            (LKColorCatalogue.separator, .separator),
            (LKColorCatalogue.textPrimary, .label),
            (LKColorCatalogue.textSecondary, .secondaryLabel),
            (LKColorCatalogue.textTertiary, .tertiaryLabel),
            (LKColorCatalogue.islandBackground, .black),
        ]
        for (token, system) in expected {
            for scheme in appearances {
                #expect(
                    token.hexString(in: scheme) == LKColorToken.hexString(of: resolve(system, in: scheme)),
                    "\(token.name), \(scheme)"
                )
            }
        }
    }

    @Test func cardsLiftOffTheBackgroundInBothAppearances() {
        // lkCard() draws secondaryGroupedBackground on groupedBackground. In light mode that's
        // white on grey, in dark mode grey on black: lighter than what's behind it either way.
        for scheme in appearances {
            let card = luminance(LKColorCatalogue.secondaryGroupedBackground.resolved(in: scheme))
            let screen = luminance(LKColorCatalogue.groupedBackground.resolved(in: scheme))
            #expect(card > screen, "\(scheme): card \(card), screen \(screen)")
        }
    }

    @Test func colourFollowsTheAppearance() {
        // Dark text on light backgrounds in light mode, and the other way round in dark mode.
        let light = luminance(LKColorCatalogue.textPrimary.resolved(in: .light))
        let dark = luminance(LKColorCatalogue.textPrimary.resolved(in: .dark))
        #expect(light < 0.1)
        #expect(dark > 0.9)
        #expect(!LKColorCatalogue.groupedBackground.isFixed)
        #expect(!LKColorCatalogue.tint.isFixed)
    }

    @Test func theIslandIsAlwaysBlack() {
        #expect(LKColorCatalogue.islandBackground.isFixed)
        #expect(LKColorCatalogue.islandBackground.hexString(in: .dark) == "#000000")
    }
}
