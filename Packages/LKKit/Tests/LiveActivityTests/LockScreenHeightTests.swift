import SwiftUI
import Testing
import UIKit
@testable import LiveActivity

/// The system may truncate a Lock Screen Live Activity taller than 160 points (CLAUDE.md,
/// SPEC.md §3). StandBy scales that same view up rather than laying it out again, so its layout
/// gets the same limit. Nothing in the Lab or its snapshots shows an overflow, so measure it here.
@Suite struct LockScreenHeightTests {
    /// Where the system starts cutting content off.
    private static let maxHeight: CGFloat = 160
    /// The Live Activity Lab's Lock Screen width, an iPhone 16 Pro's. Every line of text in these
    /// layouts is one line, so a narrower phone doesn't make them taller.
    private static let width: CGFloat = 371

    @Test(arguments: LiveActivitySamples.catalogue(), [LockScreenView.Layout.lockScreen, .standBy])
    @MainActor func staysUnder160Points(sample: LiveActivitySample, layout: LockScreenView.Layout) {
        let view = LockScreenView(attributes: sample.attributes, state: sample.state, layout: layout)
            .fixedSize(horizontal: false, vertical: true)
        let size = UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude))
        #expect(size.height > 0, "\(sample.id), \(layout): nothing laid out")
        #expect(size.height <= Self.maxHeight, "\(sample.id), \(layout): \(size.height) points tall")
    }
}
