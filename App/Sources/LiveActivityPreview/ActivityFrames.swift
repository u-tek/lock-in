import DesignSystem
import LiveActivity
import Model
import SwiftUI

// The system's chrome around each Live Activity presentation, so the Live Activity Lab can show
// the LiveActivity module's views roughly as the system would. Only the views inside are real.
// The island's cut-out, the Lock Screen's wallpaper and the activity's default background,
// StandBy's black and Always-On's dimming are the system's, and are checked on a phone through
// TestFlight (docs/decisions/0001-live-activity-views-in-package.md).

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
    /// DesignSystem's card corner is the Lock Screen activity's own, so the stand-in matches.
    static let lockScreenCornerRadius: CGFloat = LKRadius.card
    /// The Apple Watch Smart Stack's small activity family: about 160 × 70 of content inside
    /// `smartStackInset` on each side.
    static let smartStackSize = CGSize(width: 176, height: 86)
    static let smartStackInset: CGFloat = 8
    /// Between a stage row's edge and the presentation on it. The real Lock Screen leaves about
    /// 15 points each side; this is less, so a card inside a list row still gets close to its
    /// real width (about 354 of 371 points on an iPhone 16 Pro).
    static let stageInset: CGFloat = 8
}

// MARK: - Dynamic Island

// The island is always dark: the system draws its content in the dark appearance whatever the
// phone's, so system colours resolve to their dark variants there. The stand-ins do the same, or
// a light-mode screenshot would show colours the island never does.

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
        .environment(\.colorScheme, .dark)
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
            .environment(\.colorScheme, .dark)
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
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Lock Screen, StandBy, Always-On, Watch

/// The Lock Screen presentation (also the banner, StandBy and, with `.smartStack`, the Watch) on a
/// stand-in for what the system draws behind it. Put it on a stage row (`activityStageRow(_:)`):
/// the Lock Screen card is translucent, so it needs the wallpaper behind it to read as one.
///
/// - Lock Screen: the widget extension sets no `activityBackgroundTint`, so the system draws its
///   default background, a translucent platter that follows the phone's appearance. The regular
///   material is the closest thing an app can draw.
/// - Always-On: the same card, dark and dimmed, with the view in reduced luminance (outlines).
/// - StandBy: no card at all. The activity fills a black screen, always in the dark appearance.
/// - Watch: a dark platter on the watch face's black.
struct LockScreenPreview: View {
    let sample: LiveActivitySample
    let layout: LockScreenView.Layout
    let isLuminanceReduced: Bool

    init(_ sample: LiveActivitySample, layout: LockScreenView.Layout = .lockScreen, isLuminanceReduced: Bool = false) {
        self.sample = sample
        self.layout = layout
        self.isLuminanceReduced = isLuminanceReduced
    }

    var body: some View {
        switch layout {
        case .smartStack:
            content
                .padding(ActivityFrameMetrics.smartStackInset)
                .frame(width: ActivityFrameMetrics.smartStackSize.width, height: ActivityFrameMetrics.smartStackSize.height)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
                .environment(\.colorScheme, .dark)
        case .standBy:
            content
                .frame(maxWidth: ActivityFrameMetrics.lockScreenWidth)
                .environment(\.colorScheme, .dark)
        default:
            if isLuminanceReduced {
                card
                    .environment(\.colorScheme, .dark)
            } else {
                card
            }
        }
    }

    private var card: some View {
        content
            .frame(maxWidth: ActivityFrameMetrics.lockScreenWidth)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: ActivityFrameMetrics.lockScreenCornerRadius, style: .continuous)
            )
    }

    private var content: some View {
        LockScreenView(attributes: sample.attributes, state: sample.state, layout: layout)
            .environment(\.isLuminanceReduced, isLuminanceReduced)
    }
}

// MARK: - Miniatures

/// A presentation drawn smaller as a whole, for overviews such as the Lab's matrix. It's laid out
/// at its real size and then scaled, so the miniature keeps the real layout rather than squeezing
/// into less width, and it takes up only the scaled size. Give the content its real width
/// (`ActivityFrameMetrics.lockScreenWidth`, `expandedWidth`): otherwise it lays out at the width
/// offered divided by `scale`.
struct MiniaturePreview<Content: View>: View {
    let scale: CGFloat
    let content: Content

    init(scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.scale = scale
        self.content = content()
    }

    var body: some View {
        MiniatureLayout(scale: scale) {
            content
                .scaleEffect(scale)
        }
    }
}

/// Lays its one subview out at full size, centred, and takes up that size times `scale`, so the
/// subview's own `scaleEffect(scale)` (which doesn't change layout) fills exactly that space.
private struct MiniatureLayout: Layout {
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let size = subview.sizeThatFits(fullSize(proposal))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: fullSize(proposal))
    }

    /// What the miniature is offered, at full size.
    private func fullSize(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { $0 / scale }, height: proposal.height.map { $0 / scale })
    }
}

// MARK: - Stages

/// What a preview sits on.
enum ActivityBackdrop {
    /// The Lock Screen: a wallpaper in the phone's appearance. Also behind the island, which
    /// floats over whatever is on screen.
    case wallpaper
    /// The Lock Screen in Always-On: the wallpaper, dimmed almost to black.
    case dimmedWallpaper
    /// StandBy's black, and the Apple Watch face's.
    case black
}

extension View {
    /// Turns this list row into a stage for a preview: the backdrop fills the row and the
    /// preview gets nearly the row's full width, so the Lock Screen card keeps close to its real
    /// proportions. The backdrop goes in as the row's background because that's what an
    /// inset-grouped list rounds at a section's corners; row content isn't clipped.
    func activityStageRow(_ backdrop: ActivityBackdrop) -> some View {
        padding(.horizontal, ActivityFrameMetrics.stageInset)
            .padding(.vertical, LKSpacing.l)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets())
            .listRowBackground(ActivityBackdropView(backdrop: backdrop))
    }
}

private struct ActivityBackdropView: View {
    let backdrop: ActivityBackdrop

    var body: some View {
        switch backdrop {
        case .wallpaper: LockScreenWallpaper()
        case .dimmedWallpaper: LockScreenWallpaper(isDimmed: true)
        case .black: LKColor.islandBackground
        }
    }
}

/// A stand-in for a Lock Screen wallpaper (the Lab's stages, and the phone in the onboarding
/// pitch): a soft mesh of system colours in the tint's family, like the gradients iOS ships.
/// Paler in light mode and deeper in dark, as the system dims the wallpaper behind a dark Lock
/// Screen, so the translucent card reads the way it would on a phone. Only system colours, so it
/// follows the appearance like everything else.
struct LockScreenWallpaper: View {
    /// Always-On: nearly black, with a hint of the colour left.
    let isDimmed: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(isDimmed: Bool = false) {
        self.isDimmed = isDimmed
    }

    var body: some View {
        MeshGradient(width: 3, height: 3, points: Self.points, colors: Self.colors)
            .overlay { veil }
            .accessibilityHidden(true)
    }

    /// Washes the mesh towards the appearance: white over it in light mode, black in dark.
    private var veil: Color {
        if isDimmed {
            return .black.opacity(0.75)
        }
        return colorScheme == .dark ? .black.opacity(0.4) : .white.opacity(0.35)
    }

    /// A 3 × 3 grid with its centre pulled up and to the right, so the colour drifts rather than
    /// sitting in bands.
    private static let points: [SIMD2<Float>] = [
        .init(0, 0), .init(0.5, 0), .init(1, 0),
        .init(0, 0.5), .init(0.62, 0.4), .init(1, 0.5),
        .init(0, 1), .init(0.5, 1), .init(1, 1),
    ]

    /// Cool colours around the tint: blue and cyan to the left, purple to the right. Pink was
    /// tried and turned maroon under the dark veil.
    private static let colors: [Color] = [
        .blue, .indigo, .purple,
        .cyan, .indigo, .purple,
        .teal, .blue, .indigo,
    ]
}
