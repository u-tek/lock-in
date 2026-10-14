import Creature
import DesignSystem
import SwiftUI

/// Three friends locked in, as the expanded Dynamic Island shows a squad: the moment Lockin is
/// built around. Drawn by hand rather than with the Live Activity's views, so the pitch shows the
/// friends and nothing else (no buttons, no pet).
struct FriendsIsland: View {
    /// When the friends' timers were read; they count down from here.
    let now: Date

    var body: some View {
        let friends = SampleLocklings.friends
        VStack(spacing: LKSpacing.m) {
            // Beside the camera, as in the real island.
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(LKColor.focusing)
                Spacer()
                Text("\(friends.count) locked in")
                    .foregroundStyle(LKColor.textSecondary)
            }
            .font(LKFont.footnote.weight(.semibold))
            .padding(.horizontal, LKSpacing.xs)

            HStack(alignment: .top, spacing: 0) {
                ForEach(friends) { friend in
                    VStack(spacing: LKSpacing.xs) {
                        CreatureView(avatar: friend.avatar, pose: .focusing, size: 46)
                            .frame(height: 54)
                        Text(friend.name)
                            .font(LKFont.caption.weight(.medium))
                            .foregroundStyle(LKColor.textSecondary)
                        Text(timerInterval: now...now.addingTimeInterval(friend.secondsLeft), countsDown: true)
                            .font(LKFont.timerSquadmate)
                            .foregroundStyle(LKColor.focusing)
                            .multilineTextAlignment(.center)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(LKColor.islandBackground, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
        // The island is always dark, whatever the phone's appearance.
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(friends.map(\.name).formatted(.list(type: .and))) locked in, in the Dynamic Island"))
    }
}

/// The top of a phone, with the island over a wallpaper, fading out below.
struct PhoneTopMock: View {
    let now: Date

    private static let bezel: CGFloat = 6
    private static let corner: CGFloat = 54

    var body: some View {
        let screen = UnevenRoundedRectangle(topLeadingRadius: Self.corner, topTrailingRadius: Self.corner, style: .continuous)
        FriendsIsland(now: now)
            .padding(.horizontal, Self.bezel + 10)
            .padding(.top, Self.bezel + 11)
            .padding(.bottom, 48)
            .frame(maxWidth: 380)
            .background { LockScreenWallpaper() }
            .clipShape(screen)
            .overlay {
                screen.strokeBorder(LKColor.islandBackground, lineWidth: Self.bezel)
            }
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }
}
