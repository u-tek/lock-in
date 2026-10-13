import DesignSystem
import LiveActivity
import Model
import SwiftUI

// The system's chrome around each Live Activity presentation, so the app can show the
// LiveActivity module's views roughly as the system would: Home's preview and the Live Activity
// Lab. Only the views inside are real. The island's cut-out, the Lock Screen's wallpaper and
// Always-On's dimming are the system's, and are checked on a phone through TestFlight
// (docs/decisions/0001-live-activity-views-in-package.md).

/// Approximate sizes on an iPhone 16 Pro.
enum ActivityFrameMetrics {
    /// The island's height in the compact and minimal presentations.
    static let compactHeight: CGFloat = 36.67
    /// The camera and sensors between the compact leading and trailing content.
    static let sensorWidth: CGFloat = 110
    static let compactInset: CGFloat = 10
    static let minimalSize: CGFloat = 36.67
    static let expandedWidth: CGFloat = 371
    static let expandedCornerRadius: CGFloat = 44
    /// The sensors at the top of the expanded island, above the centre region.
    static let expandedSensorHeight: CGFloat = 24
    static let lockScreenWidth: CGFloat = 371
    static let lockScreenCornerRadius: CGFloat = 22
    /// The Apple Watch Smart Stack's small activity family: about 160 × 70 of content inside
    /// `smartStackInset` on each side.
    static let smartStackSize = CGSize(width: 176, height: 86)
    static let smartStackInset: CGFloat = 8
}

/// Compact: one Live Activity in the island, with content either side of the camera.
struct CompactIslandPreview: View {
    let sample: LiveActivitySample

    init(_ sample: LiveActivitySample) {
        self.sample = sample
    }

    var body: some View {
        HStack(spacing: 0) {
            CompactLeadingView(attributes: sample.attributes, state: sample.state)
            Color.clear
                .frame(width: ActivityFrameMetrics.sensorWidth)
            CompactTrailingView(attributes: sample.attributes, state: sample.state)
        }
        .padding(.horizontal, ActivityFrameMetrics.compactInset)
        .frame(height: ActivityFrameMetrics.compactHeight)
        .background(LKColor.islandBackground, in: Capsule())
        .fixedSize()
    }
}

/// Minimal: several apps' activities share the island, and this one gets a circle.
struct MinimalIslandPreview: View {
    let sample: LiveActivitySample

    init(_ sample: LiveActivitySample) {
        self.sample = sample
    }

    var body: some View {
        MinimalView(attributes: sample.attributes, state: sample.state)
            .frame(width: ActivityFrameMetrics.minimalSize, height: ActivityFrameMetrics.minimalSize)
            .background(LKColor.islandBackground, in: Circle())
    }
}

/// Expanded: leading and trailing beside the camera, the centre under it, the bottom below all.
struct ExpandedIslandPreview: View {
    let sample: LiveActivitySample

    init(_ sample: LiveActivitySample) {
        self.sample = sample
    }

    var body: some View {
        VStack(spacing: LKSpacing.s) {
            HStack(alignment: .top, spacing: LKSpacing.s) {
                ExpandedLeadingView(attributes: sample.attributes, state: sample.state)
                VStack(spacing: LKSpacing.xs) {
                    Color.clear
                        .frame(height: ActivityFrameMetrics.expandedSensorHeight)
                    ExpandedCenterView(attributes: sample.attributes, state: sample.state)
                }
                .frame(maxWidth: .infinity)
                ExpandedTrailingView(attributes: sample.attributes, state: sample.state)
            }
            ExpandedBottomView(attributes: sample.attributes, state: sample.state)
        }
        .padding(.horizontal, 18)
        .padding(.top, LKSpacing.m)
        .padding(.bottom, 18)
        .frame(maxWidth: ActivityFrameMetrics.expandedWidth)
        .background(
            LKColor.islandBackground,
            in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.expandedCornerRadius, style: .continuous)
        )
    }
}

/// The Lock Screen presentation (also the banner, StandBy and, with `.smartStack`, the Watch) on
/// the background the widget extension tints it with.
struct LockScreenPreview: View {
    let sample: LiveActivitySample
    let layout: LockScreenView.Layout
    /// Always-On. The view switches to outlines; the black stands in for the system's dimming.
    let isLuminanceReduced: Bool

    init(_ sample: LiveActivitySample, layout: LockScreenView.Layout = .lockScreen, isLuminanceReduced: Bool = false) {
        self.sample = sample
        self.layout = layout
        self.isLuminanceReduced = isLuminanceReduced
    }

    var body: some View {
        if layout == .smartStack {
            content
                .padding(ActivityFrameMetrics.smartStackInset)
                .frame(width: ActivityFrameMetrics.smartStackSize.width, height: ActivityFrameMetrics.smartStackSize.height)
                .background(fill, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
        } else {
            content
                .frame(maxWidth: ActivityFrameMetrics.lockScreenWidth)
                .background(
                    fill,
                    in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.lockScreenCornerRadius, style: .continuous)
                )
        }
    }

    private var content: some View {
        LockScreenView(attributes: sample.attributes, state: sample.state, layout: layout)
            .environment(\.isLuminanceReduced, isLuminanceReduced)
    }

    private var fill: Color {
        isLuminanceReduced ? .black : LKColor.liveActivityBackground
    }
}
