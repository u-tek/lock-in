import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The tokens page draws itself from these lists, so they must be complete and unambiguous.
@Suite struct CatalogueTests {
    // MARK: Colour

    @Test func colourNamesAreUnique() {
        let names = LKColorCatalogue.all.map { $0.name }
        #expect(Set(names).count == names.count)
        #expect(!names.contains(""))
    }

    @Test func groupsAreNamedOnceAndNeverEmpty() {
        let names = LKColorCatalogue.groups.map { $0.name }
        #expect(Set(names).count == names.count)
        for group in LKColorCatalogue.groups {
            #expect(!group.tokens.isEmpty, "\(group.name)")
        }
    }

    @Test func everyStateAndMoodIsCatalogued() {
        let catalogued = Set(LKColorCatalogue.all)
        for tone in LKMemberTone.allCases {
            #expect(catalogued.contains(tone.token), "\(tone)")
        }
        for mood in LKColorCatalogue.petMoods {
            #expect(catalogued.contains(mood), "\(mood.name)")
        }
    }

    @Test func everyColourSaysWhatItIsAndWhereItsUsed() {
        for token in LKColorCatalogue.all {
            #expect(!token.usage.isEmpty, "\(token.name)")
            #expect(!token.uiKitName.isEmpty, "\(token.name)")
        }
    }

    @Test func everyColourResolvesToHex() {
        // The tokens page prints these; a colour that won't give up its components would print "?".
        for token in LKColorCatalogue.all {
            for scheme in appearances {
                let hex = token.hexString(in: scheme)
                #expect(hex.hasPrefix("#"), "\(token.name), \(scheme): \(hex)")
            }
        }
    }

    @Test func hexStringsAreSRGBWithAlphaWhenTranslucent() {
        #expect(LKColorToken.hexString(of: UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)) == "#FF8000")
        #expect(LKColorToken.hexString(of: UIColor(red: 0, green: 0, blue: 0, alpha: 0.29)) == "#000000 29%")
        // Display P3 colours past the edge of sRGB are clamped to it, not wrapped.
        #expect(LKColorToken.hexString(of: UIColor(red: 1.2, green: -0.1, blue: 0.5, alpha: 1)) == "#FF0080")
    }

    // MARK: Type

    @Test func typeStyleNamesAreUnique() {
        let names = LKTypeStyle.allCases.map { $0.name }
        #expect(Set(names).count == names.count)
    }

    @Test func typeStylesDescribeThemselves() {
        for style in LKTypeStyle.allCases {
            #expect(!style.usage.isEmpty, "\(style.name)")
            #expect(!style.sample.isEmpty, "\(style.name)")
        }
        #expect(LKTypeStyle.largeTitle.summary == "Large Title, 34 pt by default")
        #expect(LKTypeStyle.timerLockScreen.summary == "Title 2 semibold, 22 pt by default, monospaced digits")
        #expect(LKTypeStyle.timerStandBy.summary == "72 pt semibold, fixed, monospaced digits")
    }

    @Test func liveActivityTimersFollowTheSystemDoc() {
        // design/SYSTEM.md: Title 2 semibold on the Lock Screen, Body semibold in the island, a
        // large fixed semibold hero in StandBy.
        #expect(LKTypeStyle.timerLockScreen.textStyle == Font.TextStyle.title2)
        #expect(LKTypeStyle.timerLockScreen.weight == Font.Weight.semibold)
        #expect(LKTypeStyle.timerIsland.textStyle == Font.TextStyle.body)
        #expect(LKTypeStyle.timerIsland.weight == Font.Weight.semibold)
        for style in [LKTypeStyle.timerStandBy, .timerStandBySmall] {
            #expect(style.textStyle == nil, "\(style.name)")
            #expect(style.weight == Font.Weight.semibold, "\(style.name)")
        }
        #expect(LKTypeStyle.timerStandBy.pointSize > LKTypeStyle.timerStandBySmall.pointSize)
    }

    @Test func onlyTimersHaveMonospacedDigitsOrExtraWeight() {
        #expect(LKTypeStyle.allCases.filter { $0.isTimer }.count == 6)
        for style in LKTypeStyle.allCases {
            #expect(style.hasMonospacedDigits == style.isTimer, "\(style.name)")
            // Text keeps its style's own weight; only timers add one.
            #expect((style.weight != nil) == style.isTimer, "\(style.name)")
        }
    }

    @Test func onlyTheBigTimersAreFixedSizes() {
        let fixed = LKTypeStyle.allCases.filter { !$0.scalesWithDynamicType }
        #expect(Set(fixed) == Set<LKTypeStyle>([.timerApp, .timerStandBy, .timerStandBySmall]))
        for style in fixed {
            #expect(style.pointSize >= 40, "\(style.name)")
        }
    }

    @Test func everyStyleIsItsOwnFont() {
        // No two catalogue entries collapse into the same font, so each row on the tokens page
        // shows something different.
        let fonts = LKTypeStyle.allCases.map { $0.font }
        #expect(Set(fonts).count == fonts.count)
    }

    @Test @MainActor func scaledStylesListTheSystemDefaultSize() {
        // The tokens page prints pointSize beside each style, and the Live Activity reserves
        // countdown widths from it; check it against the system's own size at the default
        // (Large) text size.
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        for style in LKTypeStyle.allCases {
            guard let textStyle = style.textStyle else { continue }
            guard let uiStyle = uiTextStyle(textStyle) else {
                Issue.record("No UIKit text style for \(style.name)")
                continue
            }
            let systemSize = UIFont.preferredFont(forTextStyle: uiStyle, compatibleWith: traits).pointSize
            #expect(systemSize == style.pointSize, "\(style.name): system \(systemSize), catalogue \(style.pointSize)")
        }
    }

    // MARK: Metrics

    @Test func metricNamesAreUnique() {
        let spacing = LKSpacing.all.map { $0.name }
        let radii = LKRadius.all.map { $0.name }
        #expect(Set(spacing).count == spacing.count)
        #expect(Set(radii).count == radii.count)
    }

    @Test func scalesStepUp() {
        let spacing = [
            LKSpacing.xxs, LKSpacing.xs, LKSpacing.s, LKSpacing.m,
            LKSpacing.l, LKSpacing.xl, LKSpacing.xxl, LKSpacing.xxxl,
        ]
        #expect(spacing == spacing.sorted())
        #expect(Set(spacing).count == spacing.count)
        let radii = LKRadius.all.map { $0.value }
        #expect(radii == radii.sorted())
    }

    @Test func spacingIsOnTheFourPointGrid() {
        for metric in LKSpacing.all where metric.name != "xxs" {
            #expect(metric.value.truncatingRemainder(dividingBy: 4) == 0, "\(metric.name) \(metric.value)")
        }
        // The one half step.
        #expect(LKSpacing.xxs == 2)
    }

    @Test func cardsUseTheLiveActivityCorner() {
        // design/SYSTEM.md: hand-drawn cards use a continuous 26-point radius.
        #expect(LKRadius.card == 26)
    }
}

private func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle? {
    switch style {
    case .largeTitle: return .largeTitle
    case .title: return .title1
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption1
    case .caption2: return .caption2
    default: return nil
    }
}
