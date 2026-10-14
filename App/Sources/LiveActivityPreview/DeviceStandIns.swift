import DesignSystem
import LiveActivity
import Model
import SwiftUI

// Stand-ins for the phone around the Live Activity, for the onboarding tips' pictures and the App
// Store screenshots (M6): the pitch's squad as a Live Activity sample, a phone on its side in
// StandBy, and a phone in portrait. As in ActivityFrames.swift, only the views inside are real
// (the LiveActivity module's, the app's screens); the phone, its status bar and StandBy's black
// are drawn here.

// MARK: - The pitch's squad

/// The onboarding pitch's squad as a Live Activity: you (Sam) with Ava, Noor and Kai in Library
/// Goblins and its teen sprout, the same made-up friends the onboarding and the snapshots use.
/// Every time is relative to `now`, so the timers run from when the screen appears.
@MainActor
enum PitchActivity {
    static let squadName = "Library Goblins"
    /// Your member id.
    static let me = "uSam000001"

    /// Everyone locked in, so the compact island says "+3": the island the app is built around.
    static func squad(now: Date) -> LiveActivitySample {
        let friends = SampleLocklings.friends
        let t = now.timeIntervalSince1970
        let members = [you(at: t)] + friends.map { friend in
            // Noor's in a 50-minute session; the others' are 25.
            let length: TimeInterval = friend.secondsLeft > 25 * 60 ? 3_000 : 1_500
            return Member(
                i: "u\(friend.id)",
                n: friend.name,
                a: friend.avatar.code,
                s: MemberState.focusing.rawValue,
                b: t + friend.secondsLeft - length,
                e: t + friend.secondsLeft
            )
        }
        return sample(id: "pitch-squad", members: members)
    }

    /// A busier evening for the Lock Screen: you, Ava and Noor locked in, Kai on a break and Mia
    /// done.
    static func evening(now: Date) -> LiveActivitySample {
        let t = now.timeIntervalSince1970
        var members = squad(now: now).state.m
        if let kai = members.firstIndex(where: { $0.i == "ukai" }) {
            let old = members[kai]
            members[kai] = Member(i: old.i, n: old.n, a: old.a, s: MemberState.onBreak.rawValue, b: t - 60, e: t + 240)
        }
        let mia = SampleLocklings.avatar(body: 3, colour: 5, eyes: 0, hat: 3, includingPlus: true)
        members.append(Member(i: "umia", n: "Mia", a: mia.code, s: MemberState.done.rawValue, b: t - 1_600, e: t - 100))
        return sample(id: "pitch-evening", members: members)
    }

    private typealias Member = LockinAttributes.ContentState.Member

    /// You, ten minutes into 25, as in the other samples.
    private static func you(at t: TimeInterval) -> Member {
        Member(i: me, n: "Sam", a: SampleLocklings.you.code, s: MemberState.focusing.rawValue, b: t - 600, e: t + 900)
    }

    private static func sample(id: String, members: [Member]) -> LiveActivitySample {
        LiveActivitySample(
            id: id,
            title: squadName,
            attributes: LockinAttributes(sid: "r7Kq2xP9aL", me: me, sq: squadName),
            state: LockinAttributes.ContentState(
                v: 12,
                m: members,
                p: LockinAttributes.ContentState.Pet(k: "sprout.2", md: 3, x: 0.64)
            )
        )
    }
}

// MARK: - StandBy

/// A phone on its side in StandBy ("desk mode", SPEC.md §1.7): the Lock Screen view in its
/// StandBy layout on black, as large as the screen allows without drawing it bigger than it is.
/// The system scales it up to fill a real phone's screen.
struct StandByPhone: View {
    let sample: LiveActivitySample
    /// The screen's width; its height keeps an iPhone 16 Pro's proportions on its side.
    let width: CGFloat

    /// Height over width of the screen on its side (402 × 874 points upright).
    static let aspect: CGFloat = 402 / 874
    /// Room the StandBy layout needs, about 153 points at the default text size, and a little
    /// more.
    static let contentHeight: CGFloat = 160

    var body: some View {
        let height = width * Self.aspect
        let corner = width * 0.09
        let bezel = max(4, width * 0.022)
        let scale = min(1, (width - 24) / ActivityFrameMetrics.lockScreenWidth, (height - 8) / Self.contentHeight)
        ZStack {
            LKColor.islandBackground
            MiniaturePreview(scale: scale) {
                LockScreenPreview(sample, layout: .standBy)
                    .frame(width: ActivityFrameMetrics.lockScreenWidth)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .padding(bezel)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: corner + bezel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner + bezel, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("A phone on its side on a charger, showing the squad's timers"))
    }
}

/// The charging stand under `StandByPhone`: a stem and a base, in a shape style that suits what
/// it stands on.
struct DeskStand<Style: ShapeStyle>: View {
    let width: CGFloat
    let style: Style

    var body: some View {
        VStack(spacing: 0) {
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(style)
                .frame(width: width * 0.16, height: width * 0.09)
            Capsule()
                .fill(style)
                .frame(width: width * 0.42, height: max(6, width * 0.03))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - A phone, upright

/// An iPhone 16 Pro drawn round a screen, at `scale`: the screen is laid out at its real size,
/// 402 × 874 points, and the whole phone drawn smaller (`MiniaturePreview`).
///
/// With `insetsContent`, the screen keeps clear of the status bar and the home indicator, as a
/// screen in the app does; `background` then fills behind them. Without it, the content has the
/// whole screen and places things itself (a Lock Screen, a Home Screen).
struct PhoneStandIn<Screen: View>: View {
    var scale: CGFloat
    var insetsContent = true
    var background: Color = .clear
    /// The time in the status bar; the Lock Screen shows a big clock instead.
    var showsTime = true
    /// Off where the screen's own island covers it (expanded).
    var showsStatusBar = true
    /// The island at rest. Off where the screen draws an island of its own (expanded).
    var showsIsland = true
    @ViewBuilder let screen: () -> Screen

    static var screenSize: CGSize { CGSize(width: 402, height: 874) }
    static var statusBarHeight: CGFloat { 54 }
    static var homeIndicatorHeight: CGFloat { 34 }
    static var screenCorner: CGFloat { 55 }
    static var bezel: CGFloat { 12 }

    var body: some View {
        MiniaturePreview(scale: scale) {
            phone
        }
    }

    private var phone: some View {
        ZStack(alignment: .top) {
            background
            screen()
                .padding(.top, insetsContent ? Self.statusBarHeight : 0)
                .padding(.bottom, insetsContent ? Self.homeIndicatorHeight : 0)
                .frame(width: Self.screenSize.width, height: Self.screenSize.height, alignment: .top)
            if showsStatusBar {
                StatusBarStandIn(showsTime: showsTime)
            }
            if showsIsland {
                Capsule()
                    .fill(LKColor.islandBackground)
                    .frame(width: 126, height: 37)
                    .padding(.top, 11)
            }
            Capsule()
                .fill(.primary)
                .frame(width: 140, height: 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
        }
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.screenCorner, style: .continuous))
        .padding(Self.bezel)
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: Self.screenCorner + Self.bezel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Self.screenCorner + Self.bezel, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 2)
        }
    }
}

/// The status bar at 9:41 with full bars, as in every snapshot.
struct StatusBarStandIn: View {
    var showsTime = true

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "9:41")
                .font(.system(size: 17, weight: .semibold))
                .opacity(showsTime ? 1 : 0)
                .frame(width: 120)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 120)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .frame(height: PhoneStandIn<EmptyView>.statusBarHeight)
        .accessibilityHidden(true)
    }
}
