import Creature
import DesignSystem
import Model
import SwiftUI

// The onboarding's pages. Each holds only its picture and its few words; OnboardingFlow owns the
// buttons, the dots and moving between them.

/// A page's title: bold, centred, and a heading for VoiceOver.
private struct PageTitle: View {
    let text: LocalizedStringKey
    let font: Font

    init(_ text: LocalizedStringKey, font: Font = .title.weight(.bold)) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 1. The pitch: friends' timers in your Dynamic Island.
struct WelcomePage: View {
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            PhoneTopMock(now: now)
                .padding(.horizontal, LKSpacing.xl)
                .padding(.top, LKSpacing.s)
            Spacer(minLength: LKSpacing.l)
            VStack(spacing: LKSpacing.m) {
                PageTitle("Lock in with your friends.", font: LKFont.largeTitle.weight(.bold))
                Text("Their timers live in your Dynamic Island.")
                    .font(LKFont.body)
                    .foregroundStyle(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, LKSpacing.xl)
            Spacer(minLength: LKSpacing.l)
        }
    }
}

/// 2. Make your Lockling.
struct LocklingPage: View {
    @Binding var avatar: AvatarCode
    let isPlus: Bool
    let onLockedOption: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                PageTitle("Make your Lockling")
                    .padding(.horizontal, LKSpacing.xl)
                    .padding(.top, LKSpacing.s)
                Spacer(minLength: LKSpacing.s)
                LocklingEditor(
                    avatar: $avatar,
                    isPlus: isPlus,
                    onLockedOption: onLockedOption,
                    heroSize: Self.heroSize(for: proxy.size.height)
                )
                Spacer(minLength: LKSpacing.s)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// As big as the page allows, up to 180 points. The title, the part tabs and the choices take
    /// about 250 points; the creature's disc is 1.3 times its size.
    static func heroSize(for height: CGFloat) -> CGFloat {
        min(180, max(100, (height - 250) / 1.3))
    }
}

/// 3. Notifications, asked for with the reason in the picture: a friend locking in.
struct NotificationsPage: View {
    let friend: AvatarCode
    @State private var rings = 0

    var body: some View {
        VStack(spacing: LKSpacing.xxl) {
            Spacer(minLength: 0)
            ZStack(alignment: .topTrailing) {
                LocklingHero(avatar: friend, pose: .focusing, size: 130)
                Image(systemName: "bell.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(LKColor.tint.gradient, in: Circle())
                    .symbolEffect(.bounce, value: rings)
                    .offset(x: 4, y: 2)
            }
            .accessibilityHidden(true)
            PageTitle("Know when your friends lock in")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LKSpacing.xl)
        .task {
            // Rings once the page has slid in.
            try? await Task.sleep(for: .milliseconds(450))
            rings += 1
        }
    }
}

/// 4. The first lock-in, ready to go.
struct ReadyPage: View {
    let avatar: AvatarCode

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: LKSpacing.xl) {
                Spacer(minLength: 0)
                LocklingHero(
                    avatar: avatar,
                    pose: .focusing,
                    size: min(170, max(110, proxy.size.height * 0.34)),
                    backdrop: .halo
                )
                .accessibilityHidden(true)
                VStack(spacing: LKSpacing.xs) {
                    PageTitle("Your first lock-in", font: .title3.weight(.semibold))
                        .foregroundStyle(LKColor.textSecondary)
                    Text("\(SessionPreset.twentyFive.minutes) min")
                        .font(.system(size: 64, weight: .bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LKSpacing.xl)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
