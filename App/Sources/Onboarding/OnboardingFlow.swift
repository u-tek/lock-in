import Core
import DesignSystem
import Model
import Paywall
import SessionEngine
import SwiftUI
import UserNotifications

/// The first run (SPEC.md §1.1): the pitch, your Lockling, notifications, then a first 25-minute
/// lock-in. One idea per page and almost no words; the button at the bottom always moves on.
struct OnboardingFlow: View {
    enum Step: Int, CaseIterable {
        case welcome
        case lockling
        case notifications
        case ready
    }

    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    /// The first lock-in has started: Home takes over.
    let onFinish: () -> Void

    @State private var step: Step
    @State private var draft: AvatarCode
    @State private var showsPaywall = false
    @State private var isAskingForNotifications = false
    /// When the pitch's made-up timers were read.
    @State private var now: Date

    private var analytics: Analytics { AppServices.analytics }

    init(engine: SessionEngine, plus: PlusStore, step: Step = .welcome, now: Date = Date(), onFinish: @escaping () -> Void) {
        self.engine = engine
        self.plus = plus
        self.onFinish = onFinish
        _step = State(initialValue: step)
        _draft = State(initialValue: engine.avatar)
        _now = State(initialValue: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: draft)
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        Group {
            switch step {
            case .welcome:
                WelcomePage(now: now)
            case .lockling:
                LocklingPage(avatar: $draft, isPlus: plus.isPlus) {
                    showsPaywall = true
                }
            case .notifications:
                NotificationsPage(friend: SampleLocklings.friends[1].avatar)
            case .ready:
                ReadyPage(avatar: draft)
            }
        }
        .id(step)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(x: 32)),
                removal: .opacity.combined(with: .offset(x: -32))
            )
        )
    }

    // MARK: - Bars

    private var topBar: some View {
        ZStack {
            PageDots(count: Step.allCases.count, current: step.rawValue)
            HStack {
                if let previous = Step(rawValue: step.rawValue - 1) {
                    Button {
                        go(to: previous)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonBorderShape(.circle)
                    .lkSecondaryButton()
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
        }
        .frame(height: 44)
        .padding(.horizontal, LKSpacing.l)
    }

    /// The main button, and under it a quiet second choice where a page has one. The second
    /// choice's space is kept on every page, so the main button never jumps between pages.
    private var bottomBar: some View {
        VStack(spacing: LKSpacing.xs) {
            Button(action: primaryAction) {
                Group {
                    if step == .ready {
                        Label("Lock in", systemImage: "lock.fill")
                    } else {
                        Text(primaryTitle)
                    }
                }
                .font(LKFont.headline)
                .frame(maxWidth: .infinity)
            }
            .lkProminentButton()
            .controlSize(.large)
            .disabled(isAskingForNotifications)

            Button("Not now") {
                analytics.track(.notificationsDeclined)
                go(to: .ready)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .opacity(step == .notifications ? 1 : 0)
            .disabled(step != .notifications)
            .accessibilityHidden(step != .notifications)
        }
        .padding(.horizontal, LKSpacing.xl)
        .padding(.bottom, LKSpacing.s)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .lockling: "That's me"
        case .notifications: "Allow"
        case .ready: "Lock in"
        }
    }

    // MARK: - Actions

    private func primaryAction() {
        switch step {
        case .welcome:
            analytics.track(.onboardingStarted)
            go(to: .lockling)
        case .lockling:
            engine.avatar = draft
            analytics.track(.creaturePicked)
            go(to: .notifications)
        case .notifications:
            isAskingForNotifications = true
            Task {
                let allowed = await NotificationPermission.request()
                analytics.track(allowed ? .notificationsAllowed : .notificationsDeclined)
                isAskingForNotifications = false
                go(to: .ready)
            }
        case .ready:
            engine.start(minutes: SessionPreset.twentyFive.minutes)
            onFinish()
        }
    }

    private func go(to next: Step) {
        withAnimation(.smooth(duration: 0.35)) {
            step = next
        }
    }
}

/// Where you are in the flow: a dot per page, the current one long.
private struct PageDots: View {
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
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}

/// Whether the first run has been finished, kept in the App Group so it outlives an update.
enum OnboardingState {
    static let defaultsKey = "LKOnboardingCompleted"

    static func isComplete(defaults: UserDefaults? = AppGroup.defaults()) -> Bool {
        (defaults ?? .standard).bool(forKey: defaultsKey)
    }

    static func markComplete(defaults: UserDefaults? = AppGroup.defaults()) {
        (defaults ?? .standard).set(true, forKey: defaultsKey)
    }
}

/// The system's notification prompt.
enum NotificationPermission {
    /// Asks once; afterwards the system answers without asking. Off the main actor because the
    /// notification centre isn't `Sendable`.
    nonisolated static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.push.error("Notification permission request failed")
            return false
        }
    }
}
