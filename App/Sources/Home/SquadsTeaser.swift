import DesignSystem
import SwiftUI

/// "Lock in with friends": what squads will look like, and a way to bring friends now. Squads
/// themselves arrive with accounts (M2, M3); inviting is free, always (SPEC.md §2).
struct SquadsTeaser: View {
    @State private var now: Date

    init(now: Date) {
        _now = State(initialValue: now)
    }

    var body: some View {
        VStack(spacing: LKSpacing.xl) {
            FriendsIsland(now: now)
                .frame(maxWidth: 380)
                .padding(.top, LKSpacing.xxl)

            VStack(spacing: LKSpacing.s) {
                Text("Squads are coming soon")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your friends' timers, right in your Dynamic Island.")
                    .font(LKFont.body)
                    .foregroundStyle(LKColor.textSecondary)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            ShareLink(item: "Lock in with me on Lockin") {
                Label("Invite friends", systemImage: "square.and.arrow.up")
                    .font(LKFont.headline)
                    .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
        }
        .padding(.horizontal, LKSpacing.xl)
        .padding(.bottom, LKSpacing.l)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Tall enough for the island, the words and the button on an iPhone SE; .medium isn't.
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
    }
}
