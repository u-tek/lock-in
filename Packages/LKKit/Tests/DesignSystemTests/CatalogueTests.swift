import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

/// The design lab draws its tokens page from these lists, so they must be complete and
/// unambiguous.
@Suite struct CatalogueTests {
    @Test func colourNamesAreUnique() {
        let names = LKPalette.all.map { $0.name }
        #expect(Set(names).count == names.count)
        #expect(!names.contains(""))
    }

    @Test func groupsAreNamedOnceAndNeverEmpty() {
        let names = LKPalette.groups.map { $0.name }
        #expect(Set(names).count == names.count)
        for group in LKPalette.groups {
            #expect(!group.tokens.isEmpty, "\(group.name)")
        }
    }

    @Test func everyStateAndMoodIsCatalogued() {
        let catalogued = Set(LKPalette.all)
        for tone in LKMemberTone.allCases {
            #expect(catalogued.contains(tone.token), "\(tone)")
        }
        for mood in LKPalette.petMoods {
            #expect(catalogued.contains(mood), "\(mood.name)")
        }
    }

    @Test func everyColourSaysWhereItsUsed() {
        for token in LKPalette.all {
            #expect(!token.usage.isEmpty, "\(token.name)")
        }
    }

    @Test func typeStyleNamesAreUnique() {
        let names = LKTypeStyle.allCases.map { $0.name }
        #expect(Set(names).count == names.count)
    }

    @Test func typeStylesDescribeThemselves() {
        for style in LKTypeStyle.allCases {
            #expect(!style.usage.isEmpty, "\(style.name)")
            #expect(!style.sample.isEmpty, "\(style.name)")
        }
        #expect(LKTypeStyle.display.summary == "34 pt bold, scales from Large Title")
        #expect(LKTypeStyle.caption.summary == "12 pt medium, scales from Caption")
        #expect(LKTypeStyle.timerCompact.summary == "15 pt semibold, fixed, monospaced digits")
    }

    @Test func timersAreFixedSizeWithMonospacedDigits() {
        let timers = LKTypeStyle.allCases.filter { $0.isTimer }
        #expect(timers.count == 4)
        for style in LKTypeStyle.allCases {
            #expect(style.hasMonospacedDigits == style.isTimer, "\(style.name)")
            #expect(style.scalesWithDynamicType == !style.isTimer, "\(style.name)")
        }
    }

    @Test @MainActor func scaledStylesListTheSystemDefaultSize() {
        // The lab prints pointSize beside each style; check it against the system's own size at
        // the default (Large) text size.
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
