import DesignSystem
import LiveActivity
import SwiftUI

/// M0's home: what the app is, a preview of the squad on the Lock Screen, and the Developer
/// menu. Nothing here pretends to work yet; solo sessions arrive in M1.
struct HomeScreen: View {
    let showsDeveloperTools: Bool
    /// The instant the preview's timers count from. Held in state so the preview doesn't restart
    /// whenever the parent redraws.
    @State private var previewDate: Date

    init(showsDeveloperTools: Bool, previewDate: Date = Date()) {
        self.showsDeveloperTools = showsDeveloperTools
        _previewDate = State(initialValue: previewDate)
    }

    var body: some View {
        // Everyone focusing, so the island reads "+3": the moment the product is built around.
        let sample = LiveActivitySamples.squadOfFour(now: previewDate)
        ScrollView {
            VStack(alignment: .leading, spacing: LKSpacing.xl) {
                VStack(alignment: .leading, spacing: LKSpacing.s) {
                    Text("Lock in with your friends.")
                        .lkType(.display)
                        .foregroundStyle(LKColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your squad's focus timers sit in your Dynamic Island and on your Lock Screen while you work.")
                        .font(LKFont.body)
                        .foregroundStyle(LKColor.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: LKSpacing.m) {
                    LKSectionHeader("Preview", detail: "A made-up squad")
                    CompactIslandPreview(sample)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    LockScreenPreview(sample)
                }

                VStack(alignment: .leading, spacing: LKSpacing.s) {
                    LKPill("Coming in the next build", systemImage: "hammer.fill")
                    Text("Solo sessions of 25, 50 or 90 minutes, with your own Live Activity. Squads follow once accounts arrive.")
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .lkCard()

                if showsDeveloperTools {
                    NavigationLink(value: AppRoute.developer) {
                        DeveloperEntry()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LKSpacing.gutter)
            .padding(.top, LKSpacing.xl)
            .padding(.bottom, LKSpacing.xxxl)
        }
        .lkScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The way into the APNs spike, the Live Activity Lab and the design tokens. Shown while
/// `LK_DEVELOPER_TOOLS` is YES, which stays on in TestFlight builds until launch.
private struct DeveloperEntry: View {
    var body: some View {
        HStack(spacing: LKSpacing.m) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LKColor.accentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer")
                    .font(LKFont.headline)
                    .foregroundStyle(LKColor.textPrimary)
                Text("APNs spike, Live Activity Lab, design tokens")
                    .font(LKFont.caption)
                    .foregroundStyle(LKColor.textSecondary)
            }
            Spacer(minLength: LKSpacing.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LKColor.textTertiary)
                .accessibilityHidden(true)
        }
        .lkCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
