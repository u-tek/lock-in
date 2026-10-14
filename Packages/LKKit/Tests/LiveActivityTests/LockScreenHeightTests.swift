import SwiftUI
import Testing
import UIKit
@testable import LiveActivity

/// The system may truncate a Lock Screen Live Activity taller than 160 points (CLAUDE.md,
/// SPEC.md §3). StandBy scales that same view up rather than laying it out again, so its layout
/// gets the same limit. Nothing in the Lab or its snapshots shows an overflow, so measure it here.
///
/// The text is Dynamic Type, so the height depends on the reader's text size. Each layout holds
/// it to the sizes it has room for (`ActivityTextSize`), so it's measured at the default size and
/// at the largest accessibility size, which the view must bring back down to the top of its range.
@Suite struct LockScreenHeightTests {
    /// Where the system starts cutting content off.
    private static let maxHeight: CGFloat = 160
    /// The Live Activity Lab's Lock Screen width, an iPhone 16 Pro's. Every line of text in these
    /// layouts is one line, so a narrower phone doesn't make them taller.
    private static let width: CGFloat = 371

    @Test(arguments: LiveActivitySamples.catalogue(), [LockScreenView.Layout.lockScreen, .standBy])
    @MainActor func staysUnder160Points(sample: LiveActivitySample, layout: LockScreenView.Layout) {
        let height = Self.height(of: sample, layout: layout, textSize: .large)
        #expect(height > 0, "\(sample.id), \(layout): nothing laid out")
        #expect(height <= Self.maxHeight, "\(sample.id), \(layout): \(height) points tall")
    }

    @Test(arguments: LiveActivitySamples.catalogue(), [LockScreenView.Layout.lockScreen, .standBy])
    @MainActor func staysUnder160PointsAtTheLargestTextSize(sample: LiveActivitySample, layout: LockScreenView.Layout) {
        let height = Self.height(of: sample, layout: layout, textSize: .accessibility5)
        #expect(height > 0, "\(sample.id), \(layout): nothing laid out")
        #expect(height <= Self.maxHeight, "\(sample.id), \(layout): \(height) points tall at the largest text size")
    }

    /// What keeps the largest size in: a reader at any size past the top of the layout's range
    /// gets the layout at the top of it. The Lock Screen goes one step past the default; StandBy
    /// stays at the default, because the system scales it up already.
    @Test(arguments: [
        (LockScreenView.Layout.lockScreen, DynamicTypeSize.xLarge),
        (LockScreenView.Layout.standBy, DynamicTypeSize.large),
    ])
    @MainActor func textSizeIsHeldToTheLayoutsRange(layout: LockScreenView.Layout, top: DynamicTypeSize) {
        let sample = LiveActivitySamples.squadOfSix(now: LiveActivitySamples.fixtureDate)
        let atTop = Self.height(of: sample, layout: layout, textSize: top)
        for size in [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility1, .accessibility5] where size > top {
            #expect(Self.height(of: sample, layout: layout, textSize: size) == atTop, "\(layout) at \(size)")
        }
    }

    /// Held, not frozen: on the Lock Screen the text does grow with the reader's size, up to the
    /// top of the range, as the rest of the system's does. The squad layout is all text but the
    /// Locklings, so it grows by several points a step.
    @Test @MainActor func lockScreenTextGrowsWithDynamicType() {
        let sample = LiveActivitySamples.squadOfSix(now: LiveActivitySamples.fixtureDate)
        let standard = Self.height(of: sample, layout: .lockScreen, textSize: .large)
        let larger = Self.height(of: sample, layout: .lockScreen, textSize: .xLarge)
        #expect(larger > standard, "\(standard) → \(larger)")
    }

    @MainActor
    private static func height(
        of sample: LiveActivitySample,
        layout: LockScreenView.Layout,
        textSize: DynamicTypeSize
    ) -> CGFloat {
        let view = LockScreenView(attributes: sample.attributes, state: sample.state, layout: layout)
            .dynamicTypeSize(textSize)
            .fixedSize(horizontal: false, vertical: true)
        return UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }
}
