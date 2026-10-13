import SwiftUI
import Testing
@testable import DesignSystem

@Suite struct ContrastTests {
    @Test func textIsReadableOnEveryBackground() {
        for scheme in appearances {
            for background in [LKPalette.background, LKPalette.surface, LKPalette.surfaceRaised] {
                let primary = LKPalette.textPrimary.contrastRatio(on: background, in: scheme)
                let secondary = LKPalette.textSecondary.contrastRatio(on: background, in: scheme)
                // Primary text clears AAA; secondary clears AA, so it can carry real information.
                #expect(primary >= 7, "textPrimary on \(background.name), \(scheme): \(primary)")
                #expect(secondary >= 4.5, "textSecondary on \(background.name), \(scheme): \(secondary)")
            }
        }
    }

    @Test func tertiaryAndAccentTextAreReadable() {
        for scheme in appearances {
            for background in [LKPalette.background, LKPalette.surface] {
                let tertiary = LKPalette.textTertiary.contrastRatio(on: background, in: scheme)
                let accent = LKPalette.accentText.contrastRatio(on: background, in: scheme)
                #expect(tertiary >= 3, "textTertiary on \(background.name), \(scheme): \(tertiary)")
                #expect(accent >= 4.5, "accentText on \(background.name), \(scheme): \(accent)")
            }
        }
    }

    @Test func labelsOnTheAccentAreReadable() {
        for scheme in appearances {
            let ratio = LKPalette.onAccent.contrastRatio(on: LKPalette.accent, in: scheme)
            #expect(ratio >= 4.5, "onAccent on accent, \(scheme): \(ratio)")
        }
    }

    @Test func liveActivityTokensAreFixed() {
        // The activity is a night window in both appearances, and the island is always black.
        #expect(LKPalette.liveActivityBackground.isFixed)
        #expect(LKPalette.islandBackground.isFixed)
        #expect(LKPalette.islandBackground.dark == RGB(hex: 0x000000))
        #expect(LKPalette.onAccent.isFixed)
        #expect(!LKPalette.background.isFixed)
    }

    @Test func liveActivityTextIsReadable() {
        for background in [LKPalette.liveActivityBackground, LKPalette.islandBackground] {
            let primary = LKPalette.textPrimary.contrastRatio(on: background, in: .dark)
            let secondary = LKPalette.textSecondary.contrastRatio(on: background, in: .dark)
            #expect(primary >= 7, "textPrimary on \(background.name): \(primary)")
            #expect(secondary >= 4.5, "textSecondary on \(background.name): \(secondary)")
        }
    }

    @Test func focusingWearsTheAccent() {
        #expect(LKPalette.focusing.dark == LKPalette.accent.dark)
        #expect(LKPalette.focusing.light == LKPalette.accentText.light)
    }

    @Test func valuesFollowTheAppearance() {
        #expect(LKPalette.background.value(in: .dark) == RGB(hex: 0x0D0B17))
        #expect(LKPalette.background.value(in: .light) == RGB(hex: 0xF6F4FC))
    }
}
