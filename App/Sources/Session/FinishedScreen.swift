import Creature
import DesignSystem
import Model
import SessionEngine
import SwiftUI

/// The end of a session: the Lockling celebrates, the coins land. After the very first one it
/// also mentions friends and Plus (SPEC.md §2's first paywall moment, solo until squads exist),
/// never in the way of Done.
struct FinishedScreen: View {
    let record: SessionRecord
    let avatar: AvatarCode
    /// Show the "Lock in with friends?" card.
    let offersFriends: Bool
    let onPlus: () -> Void
    let onDone: () -> Void

    @State private var cheers = 0

    var body: some View {
        GeometryReader { proxy in
            let hero = min(180, max(100, proxy.size.height * (offersFriends ? 0.22 : 0.3)))
            VStack(spacing: 0) {
                Spacer(minLength: LKSpacing.l)
                celebration(size: hero)
                VStack(spacing: LKSpacing.xs) {
                    HStack(spacing: LKSpacing.s) {
                        Image(systemName: LockinSymbol.coin)
                            .foregroundStyle(LockinColour.coin)
                        Text(coinsText)
                            .monospacedDigit()
                    }
                    .font(LKFont.largeTitle.weight(.bold))
                    Text(minutesText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(LKColor.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, LKSpacing.l)
                .accessibilityElement(children: .combine)
                Spacer(minLength: LKSpacing.l)
                if offersFriends {
                    FriendsCard(onPlus: onPlus)
                        .padding(.bottom, LKSpacing.l)
                }
                Button(action: onDone) {
                    Text("Done")
                        .font(LKFont.headline)
                        .frame(maxWidth: .infinity)
                }
                .lkProminentButton()
                .controlSize(.large)
            }
            .padding(.horizontal, LKSpacing.xl)
            .padding(.bottom, LKSpacing.l)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background {
            LinearGradient(colors: [LKColor.done.opacity(0.22), LKColor.done.opacity(0)], startPoint: .top, endPoint: .center)
                .background(Color(uiColor: .systemBackground))
                .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: cheers)
        .task {
            cheers += 1
        }
    }

    /// The Lockling with a couple of sparkles that bounce as the screen arrives.
    private func celebration(size: CGFloat) -> some View {
        LocklingHero(avatar: avatar, pose: record.completed ? .celebrating : .done, size: size, backdrop: .halo)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.24, weight: .semibold))
                    .foregroundStyle(LockinColour.coin)
                    .symbolEffect(.bounce, value: cheers)
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.14, weight: .semibold))
                    .foregroundStyle(LKColor.tint)
                    .symbolEffect(.bounce, value: cheers)
                    .padding(size * 0.12)
            }
            .accessibilityHidden(true)
    }

    private var coinsText: String {
        record.coinsEarned == 1 ? "+1 coin" : "+\(record.coinsEarned) coins"
    }

    private var minutesText: String {
        let minutes = record.completed ? record.plannedMinutes : record.focusedSeconds / 60
        return minutes == 1 ? "1 minute locked in" : "\(minutes) minutes locked in"
    }
}

/// After the first session: friends are the point, and they're coming. Plus is the quiet second
/// action.
private struct FriendsCard: View {
    let onPlus: () -> Void

    var body: some View {
        VStack(spacing: LKSpacing.l) {
            HStack(spacing: LKSpacing.m) {
                LKIconTile(systemName: "person.2.fill", color: LKColor.tint, size: 40)
                VStack(alignment: .leading, spacing: LKSpacing.xxs) {
                    Text("Lock in with friends?")
                        .font(LKFont.headline)
                    Text("Squads are coming soon.")
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            Button(action: onPlus) {
                Label("Get Lockin Plus", systemImage: LockinSymbol.plus)
                    .font(LKFont.headline)
                    .frame(maxWidth: .infinity)
            }
            .lkSecondaryButton()
            .controlSize(.large)
        }
        .padding(LKSpacing.l)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
    }
}
