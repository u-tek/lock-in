import API
import DesignSystem
import LiveActivity
import Model
import Paywall
import SessionEngine
import Social
import SwiftUI
import WidgetKit
import WidgetViews

// The App Store's 6.9-inch screenshots (M6, docs/launch/app-store-listing.md): `store.1`…`store.5`,
// rendered on the iPhone 16 Pro Max for `[snapshots: store]` into design/appstore/6.9-<n>-light.png
// at 1320 × 2868 pixels (its 440 × 956-point screen at 3x).
//
// Each is a headline over a real screen: the LiveActivity module's presentations with the
// Lab's stand-ins round them, the widgets' own views, and the app's screens with the snapshots'
// preview models, in a phone drawn round them (`PhoneStandIn`). Not mock-ups, which keeps them
// honest under Guideline 2.3.3. The squad is the onboarding's made-up friends.

/// One App Store screenshot, by its number in the listing.
enum StoreShot: Int, CaseIterable {
    /// Friends' timers in the expanded island, over the Home Screen's widgets.
    case island = 1
    /// The squad's Live Activity on the Lock Screen.
    case lockScreen
    /// StandBy on a desk.
    case deskMode
    /// The squad's page: the pet, the streak and the week.
    case pet
    /// Home, solo: your Lockling, coins and streak.
    case solo

    /// `store.<n>`'s `<n>`.
    init?(routePart: String) {
        guard let number = Int(routePart) else { return nil }
        self.init(rawValue: number)
    }

    var headline: String {
        switch self {
        case .island: "Your friends, in your Dynamic Island"
        case .lockScreen: "Lock in together"
        case .deskMode: "Desk mode for study sessions"
        case .pet: "Grow a squad pet"
        case .solo: "Works solo too"
        }
    }

    var subheadline: String {
        switch self {
        case .island: "See who's still locked in, without opening a thing."
        case .lockScreen: "Your whole squad's timers, right on your Lock Screen."
        case .deskMode: "Stand your phone on its side while it charges."
        case .pet: "It grows with every minute you focus together."
        case .solo: "Earn coins, keep a streak, dress up your Lockling."
        }
    }
}

/// A screenshot: the headline on the brand's colour, the screen in a phone under it, running off
/// the bottom edge.
struct StoreScreenshot: View {
    let shot: StoreShot
    /// When the samples' timers were read.
    let now: Date

    /// How large the upright phones are drawn: about 366 of the screenshot's 440 points across.
    static let phoneScale: CGFloat = 0.86
    /// The headline's block, the same height on every screenshot so the phones line up.
    static let headlineHeight: CGFloat = 150

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: LKSpacing.xl) {
                StoreHeadline(shot: shot)
                    .frame(height: Self.headlineHeight)
                    .padding(.horizontal, LKSpacing.xxl)
                content
            }
            .padding(.top, 64)
            // The phone runs off the bottom: it's taller than what's left, and stays put at the top.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background { StoreBackground() }
            .clipped()
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private var content: some View {
        switch shot {
        case .island:
            PhoneStandIn(scale: Self.phoneScale, insetsContent: false, showsStatusBar: false, showsIsland: false) {
                IslandHomeScreen(now: now)
            }
        case .lockScreen:
            PhoneStandIn(scale: Self.phoneScale, insetsContent: false, showsTime: false) {
                SquadLockScreen(now: now)
            }
            // A Lock Screen at night: the squad's colours, and the Live Activity's dark card.
            .environment(\.colorScheme, .dark)
        case .deskMode:
            DeskScene(now: now)
        case .pet:
            PreviewModels(
                stats: SnapshotData.regular,
                account: .signedIn(SnapshotData.me),
                friends: SnapshotData.friends,
                squads: [SnapshotData.squad],
                leaderboards: [SnapshotData.squad.id: SnapshotData.leaderboard]
            ) { _, _, social in
                PhoneStandIn(scale: Self.phoneScale, background: Color(uiColor: .systemGroupedBackground)) {
                    NavigationStack {
                        SquadDetailScreen(
                            squads: social.squads,
                            friends: social.friends,
                            squadID: SnapshotData.squad.id,
                            myID: SnapshotData.me.id,
                            invite: SnapshotData.squadCode
                        )
                    }
                }
            }
        case .solo:
            PreviewModels(stats: SnapshotData.regular) { engine, plus, social in
                PhoneStandIn(scale: Self.phoneScale, background: Color(uiColor: .systemBackground)) {
                    HomeScreen(engine: engine, plus: plus, social: social)
                }
            }
        }
    }
}

/// The headline and the line under it, white on the brand's colour.
private struct StoreHeadline: View {
    let shot: StoreShot

    var body: some View {
        VStack(spacing: LKSpacing.m) {
            Text(shot.headline)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(shot.subheadline)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The tint, deepening towards purple, with a soft light from the top.
private struct StoreBackground: View {
    var body: some View {
        LinearGradient(
            colors: [LKColor.tint, LKColor.tint.mix(with: .purple, by: 0.45).mix(with: .black, by: 0.15)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            RadialGradient(colors: [.white.opacity(0.2), .clear], center: .top, startRadius: 0, endRadius: 460)
        }
    }
}

// MARK: - 1. The island

/// The Home Screen with the squad's island held open: everyone's timer at the top, and the Squad
/// pet and Lock in widgets below, as the widget extension draws them.
private struct IslandHomeScreen: View {
    let now: Date

    /// Between widgets: a medium is two smalls and this gap wide.
    private static let gap: CGFloat = 24

    var body: some View {
        let data = Self.widgetData(now: now)
        ZStack(alignment: .top) {
            LockScreenWallpaper()
            VStack(spacing: 0) {
                ExpandedIslandPreview(PitchActivity.squad(now: now))
                    .padding(.top, 9)
                VStack(spacing: Self.gap) {
                    HomeWidget(.systemMedium, content: PetWidgetContent(data: data, squadID: nil))
                    HStack(spacing: Self.gap) {
                        LockInHomeWidget(data: data, now: now)
                        HomeWidget(.systemSmall, content: PetWidgetContent(data: data, squadID: WidgetSamples.newSquad.id))
                    }
                }
                .padding(.top, 40)
            }
        }
    }

    /// Ten minutes into the squad's session: Library Goblins with all four in, six days running,
    /// and a new squad's egg.
    static func widgetData(now: Date) -> WidgetData {
        var squad = WidgetSamples.squad
        squad.streak = 6
        squad.lockedIn = 4
        squad.progress = 0.64
        return WidgetData(
            avatar: SampleLocklings.you.code,
            todayMinutes: 45,
            soloStreak: 3,
            squads: [squad, WidgetSamples.newSquad],
            session: WidgetData.Session(endsAt: now.addingTimeInterval(900).timeIntervalSince1970, squadName: squad.name),
            updatedAt: now.timeIntervalSince1970
        )
    }
}

// MARK: - 2. The Lock Screen

/// The Lock Screen: the clock, the Squad pet's Lock Screen widgets under it, and the squad's Live
/// Activity at the bottom with everyone's timer.
private struct SquadLockScreen: View {
    let now: Date

    var body: some View {
        let data = IslandHomeScreen.widgetData(now: now)
        let pet = PetWidgetContent(data: data, squadID: nil)
        ZStack(alignment: .top) {
            LockScreenWallpaper()
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 62)
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, LKSpacing.s)
                Text(verbatim: "9:41")
                    .font(.system(size: 104, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: LKSpacing.m) {
                    SquadPetWidgetView(content: pet, family: .accessoryCircular, isFullColor: false)
                        .frame(width: WidgetPreviewMetrics.circular.width, height: WidgetPreviewMetrics.circular.height)
                    SquadPetWidgetView(content: pet, family: .accessoryRectangular, isFullColor: false)
                        .frame(width: WidgetPreviewMetrics.rectangular.width, height: WidgetPreviewMetrics.rectangular.height)
                }
                .padding(.top, LKSpacing.xs)
                Spacer(minLength: LKSpacing.l)
                LockScreenPreview(PitchActivity.evening(now: now))
                    .padding(.horizontal, (PhoneStandIn<EmptyView>.screenSize.width - ActivityFrameMetrics.lockScreenWidth) / 2)
                    .padding(.bottom, 128)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - 3. Desk mode

/// A phone on its side in StandBy, on a stand on a desk, with a few things a desk has on it.
private struct DeskScene: View {
    let now: Date

    /// As wide as the screenshot allows.
    private static let phoneWidth: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(height: 96)
            StandByPhone(sample: PitchActivity.squad(now: now), width: Self.phoneWidth)
            ZStack(alignment: .bottom) {
                DeskStand(width: Self.phoneWidth, style: Color.white.opacity(0.4))
                HStack(alignment: .bottom) {
                    Image(systemName: "books.vertical.fill")
                    Spacer()
                    Image(systemName: "cup.and.saucer.fill")
                }
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, LKSpacing.xxl)
                .accessibilityHidden(true)
            }
            // The desk's top.
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(height: 1)
                }
        }
    }
}
