import Core
import DesignSystem
import LiveActivity
import SessionEngine
import SwiftUI

// The two tips after the first finished session (SPEC.md §1.7, docs/milestones/M6.md): the
// filmable moments the onboarding teaches, the Lock Screen and desk mode (StandBy). A small pager
// in a sheet, each tip shown once; the pictures are the Live Activity's own views.

/// One tip.
enum OnboardingTip: String, CaseIterable, Identifiable {
    case lockScreen
    case deskMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockScreen: "Lock your phone — your squad's on the Lock Screen"
        case .deskMode: "Charging on its side? That's desk mode"
        }
    }

    var message: String {
        switch self {
        case .lockScreen: "Everyone's timer, right there, without opening Lockin."
        case .deskMode: "StandBy turns your session into a big clock across the desk."
        }
    }
}

/// Which tips have been shown, kept in the App Group so an update doesn't show them again.
enum OnboardingTips {
    static let defaultsKey = "LKOnboardingTipsShown"

    /// The tips not shown yet, in order.
    static func pending(defaults: UserDefaults? = AppGroup.defaults()) -> [OnboardingTip] {
        let shown = Set((defaults ?? .standard).stringArray(forKey: defaultsKey) ?? [])
        return OnboardingTip.allCases.filter { !shown.contains($0.rawValue) }
    }

    static func markShown(_ tip: OnboardingTip, defaults: UserDefaults? = AppGroup.defaults()) {
        let store = defaults ?? .standard
        var shown = store.stringArray(forKey: defaultsKey) ?? []
        guard !shown.contains(tip.rawValue) else { return }
        shown.append(tip.rawValue)
        store.set(shown, forKey: defaultsKey)
    }
}

extension View {
    /// After a completed session, the tips not shown yet, in a sheet once the celebration has
    /// landed. Each is marked shown as its page appears, so one swiped away unseen comes after the
    /// next session instead. Never in snapshot mode.
    func onboardingTips(after record: SessionRecord) -> some View {
        modifier(OnboardingTipsPresenter(record: record))
    }
}

private struct OnboardingTipsPresenter: ViewModifier {
    let record: SessionRecord
    @State private var tips: [OnboardingTip] = []
    @State private var isPresented = false

    /// Long enough for the Lockling's cheer and the coins.
    private static let delay: Duration = .milliseconds(1_400)

    func body(content: Content) -> some View {
        content
            .task(id: record.id) {
                guard SnapshotMode.current == nil, record.completed else { return }
                let pending = OnboardingTips.pending()
                guard !pending.isEmpty else { return }
                try? await Task.sleep(for: Self.delay)
                guard !Task.isCancelled else { return }
                tips = pending
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                OnboardingTipsView(
                    tips: tips,
                    now: Date(),
                    onShown: { OnboardingTips.markShown($0) },
                    onDone: { isPresented = false }
                )
                .presentationDetents([.height(OnboardingTipsView.sheetHeight), .large])
                .presentationDragIndicator(.visible)
            }
    }
}

/// The tips as a pager: a picture, a line and a sentence each, and one button that moves on, then
/// closes.
struct OnboardingTipsView: View {
    let tips: [OnboardingTip]
    /// When the pictures' timers were read.
    let now: Date
    let onShown: (OnboardingTip) -> Void
    let onDone: () -> Void
    @State private var page: OnboardingTip

    /// Enough for the picture, two lines of title, two of text and the button at the default text
    /// size; larger text gets the large detent.
    static let sheetHeight: CGFloat = 520

    /// - Parameter startAt: the page to open on (snapshots); the first otherwise.
    init(
        tips: [OnboardingTip],
        now: Date,
        startAt: OnboardingTip? = nil,
        onShown: @escaping (OnboardingTip) -> Void = { _ in },
        onDone: @escaping () -> Void
    ) {
        self.tips = tips
        self.now = now
        self.onShown = onShown
        self.onDone = onDone
        _page = State(initialValue: startAt ?? tips.first ?? .lockScreen)
    }

    var body: some View {
        VStack(spacing: LKSpacing.l) {
            TabView(selection: $page) {
                ForEach(tips) { tip in
                    TipPage(tip: tip, now: now)
                        .tag(tip)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if tips.count > 1 {
                TipDots(count: tips.count, current: tips.firstIndex(of: page) ?? 0)
            }

            Button(action: next) {
                Text(isLast ? "Got it" : "Next")
                    .font(LKFont.headline)
                    .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
        }
        .padding(.horizontal, LKSpacing.xl)
        .padding(.top, LKSpacing.xl)
        .padding(.bottom, LKSpacing.l)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear {
            onShown(page)
        }
        .onChange(of: page) { _, shown in
            onShown(shown)
        }
    }

    private var isLast: Bool {
        page == tips.last
    }

    private func next() {
        guard let index = tips.firstIndex(of: page), index + 1 < tips.count else {
            onDone()
            return
        }
        withAnimation(.smooth) {
            page = tips[index + 1]
        }
    }
}

/// One tip: its picture over its words.
private struct TipPage: View {
    let tip: OnboardingTip
    let now: Date

    var body: some View {
        VStack(spacing: LKSpacing.l) {
            picture
                .frame(height: 236)
                .frame(maxWidth: .infinity)
            VStack(spacing: LKSpacing.s) {
                Text(tip.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(tip.message)
                    .font(LKFont.subheadline)
                    .foregroundStyle(LKColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var picture: some View {
        switch tip {
        case .lockScreen:
            LockScreenTipPicture(sample: PitchActivity.squad(now: now))
        case .deskMode:
            VStack(spacing: 0) {
                StandByPhone(sample: PitchActivity.squad(now: now), width: 300)
                DeskStand(width: 300, style: Color(uiColor: .systemGray3))
            }
        }
    }
}

/// The Lock Screen in miniature: the clock over the squad's Live Activity, on the wallpaper.
private struct LockScreenTipPicture: View {
    let sample: LiveActivitySample

    /// The card drawn at this fraction of its size.
    private static let scale: CGFloat = 0.8

    var body: some View {
        VStack(spacing: LKSpacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: "9:41")
                .font(.system(size: 46, weight: .semibold))
                .monospacedDigit()
            Spacer(minLength: LKSpacing.s)
            MiniaturePreview(scale: Self.scale) {
                LockScreenPreview(sample)
                    .frame(width: ActivityFrameMetrics.lockScreenWidth)
            }
        }
        .foregroundStyle(.primary)
        .padding(.top, LKSpacing.m)
        .padding(.bottom, LKSpacing.m)
        .frame(width: ActivityFrameMetrics.lockScreenWidth * Self.scale + 2 * LKSpacing.m)
        .frame(maxHeight: .infinity)
        .background {
            LockScreenWallpaper()
        }
        .clipShape(RoundedRectangle(cornerRadius: LKRadius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("The Lock Screen, with your squad's timers on it"))
    }
}

/// Where you are in the tips: a dot each, the current one long, as in the onboarding.
private struct TipDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .tertiaryLabel)))
                    .frame(width: index == current ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tip \(current + 1) of \(count)"))
    }
}
