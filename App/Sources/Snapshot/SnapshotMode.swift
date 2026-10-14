import LiveActivity
import Paywall
import SessionEngine
import SwiftUI
import UIKit

/// Shows screens in a fixed state for the UI snapshot exporter (`UITests/SnapshotExportTests`).
///
/// Launch argument: `-LKSnapshots home@light,home@dark,session@dark,...`. The app shows the first,
/// then steps to the next each time the exporter posts the `next` Darwin notification, so one
/// launch covers every screen. Arguments in this form land in the `UserDefaults` argument domain,
/// so they never persist.
///
/// Nothing in snapshot mode touches ActivityKit, StoreKit, the App Group or a permission prompt:
/// app screens get preview models, the spike screen gets a fixed state, and orphaned activities
/// are left alone.
struct SnapshotMode: Sendable {
    enum Appearance: String, Sendable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    struct Shot: Sendable {
        let route: String
        /// Nil follows the simulator's own appearance, as the app does outside snapshot mode.
        let appearance: Appearance?
    }

    /// Posted by the exporter after each capture.
    static let nextNotification = "com.lockin.snapshot.next"

    let shots: [Shot]

    /// The one instant every sample in this run is built from, so every screen shows the same
    /// made-up squad at the same moment.
    ///
    /// It's the launch, not a constant: SwiftUI's timers (`Text(timerInterval:)`) read the device
    /// clock, which nothing here can pin. A constant date in the past would draw every running
    /// timer at 0:00; from the launch, a timer reads as designed ("15:00" for Ava), less the few
    /// seconds before its screen is captured.
    let referenceDate: Date

    static let current: SnapshotMode? = {
        guard let list = UserDefaults.standard.string(forKey: "LKSnapshots"), !list.isEmpty else { return nil }
        let shots = list.split(separator: ",").compactMap { token -> Shot? in
            let parts = token.split(separator: "@", maxSplits: 1).map(String.init)
            guard let route = parts.first?.trimmingCharacters(in: .whitespaces), !route.isEmpty else { return nil }
            let appearance = parts.count > 1 ? Appearance(rawValue: parts[1]) : nil
            return Shot(route: route, appearance: appearance)
        }
        return shots.isEmpty ? nil : SnapshotMode(shots: shots, referenceDate: Date())
    }()
}

/// Every screen the exporter can open, by route name. `scripts/snapshot-routes.txt` lists the
/// ones CI exports; `lab.*` routes render on the iPhone 16 Pro only.
///
/// App screens get preview models (`SessionEngine.preview`, `PlusStore.preview`): no store, no
/// ActivityKit, no StoreKit, and no permission prompts. Sheets and covers are shown as screens of
/// their own.
@MainActor
enum SnapshotGallery {
    static func view(for route: String, now: Date) -> AnyView? {
        switch route {
        // First run
        case "onboarding.welcome":
            return onboarding(.welcome, now: now)
        case "onboarding.lockling":
            return onboarding(.lockling, now: now)
        case "onboarding.notifications":
            return onboarding(.notifications, now: now)
        case "onboarding.ready":
            return onboarding(.ready, now: now)

        // The app
        case "home":
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus in
                HomeScreen(engine: engine, plus: plus)
            })
        case "session":
            // The first session, so the "lock your phone" hint shows.
            return AnyView(PreviewModels(phase: SnapshotData.running(now: now), stats: SnapshotData.newcomer) { engine, plus in
                SessionCover(engine: engine, plus: plus)
            })
        case "session.paused":
            return AnyView(PreviewModels(phase: SnapshotData.paused(now: now), stats: SnapshotData.regular) { engine, plus in
                SessionCover(engine: engine, plus: plus)
            })
        case "session.disabled":
            // Live Activities switched off in Settings: the session runs, and says how to fix it.
            return AnyView(PreviewModels(
                phase: SnapshotData.running(now: now),
                stats: SnapshotData.regular,
                liveActivityProblem: .disabled
            ) { engine, plus in
                SessionCover(engine: engine, plus: plus)
            })
        case "finished":
            return AnyView(PreviewModels(phase: SnapshotData.finished(now: now), stats: SnapshotData.regular) { engine, plus in
                SessionCover(engine: engine, plus: plus)
            })
        case "finished.first":
            return AnyView(PreviewModels(phase: SnapshotData.finished(now: now), stats: SnapshotData.firstFinish) { engine, plus in
                SessionCover(engine: engine, plus: plus)
            })
        case "paywall":
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus in
                PaywallView(store: plus, avatar: engine.avatar, onClose: {})
            })
        case "settings":
            return AnyView(PreviewModels(stats: SnapshotData.regular) { engine, plus in
                SettingsScreen(engine: engine, plus: plus, onClose: {})
            })
        case "squads":
            return AnyView(SquadsTeaser(now: now))

        // Developer tools
        case "developer":
            return AnyView(NavigationStack {
                DeveloperMenu()
                    .navigationDestination(for: AppRoute.self) { route in
                        route.destination
                    }
            })
        case "spike":
            // Before Start. The live screen asks ActivityKit for everything it shows.
            return AnyView(NavigationStack {
                APNsSpikeScreen(snapshot: .preStart)
            })
        case "lab.tokens":
            return AnyView(NavigationStack {
                DesignTokensScreen()
            })
        case "lab.liveactivity":
            return AnyView(NavigationStack {
                LiveActivityLabScreen(now: now)
            })
        default:
            // One part of a lab page, for when the whole page is taller than a screenshot:
            // lab.tokens.<part>, lab.liveactivity.<part>.
            if let part = suffix(of: route, after: "lab.tokens."), let panel = DesignTokensScreen.Panel(rawValue: part) {
                return AnyView(NavigationStack {
                    DesignTokensScreen(panels: [panel])
                })
            }
            if let part = suffix(of: route, after: "lab.liveactivity."), let panel = LiveActivityLabScreen.Panel(rawValue: part) {
                return AnyView(NavigationStack {
                    LiveActivityLabScreen(now: now, panels: [panel])
                })
            }
            return nil
        }
    }

    private static func onboarding(_ step: OnboardingFlow.Step, now: Date) -> AnyView {
        AnyView(PreviewModels(stats: SnapshotData.newcomer) { engine, plus in
            OnboardingFlow(engine: engine, plus: plus, step: step, now: now, onFinish: {})
        })
    }

    private static func suffix(of route: String, after prefix: String) -> String? {
        route.hasPrefix(prefix) ? String(route.dropFirst(prefix.count)) : nil
    }
}

/// The made-up user the app screens are shot with.
@MainActor
private enum SnapshotData {
    /// Before the first session.
    static var newcomer: FocusStats {
        FocusStats(todayMinutes: 0, streakDays: 0, coins: 0, completedSessions: 0)
    }

    /// Straight after the first session: the friends card shows.
    static var firstFinish: FocusStats {
        FocusStats(todayMinutes: 25, streakDays: 1, coins: 30, completedSessions: 1)
    }

    /// A few days in.
    static var regular: FocusStats {
        FocusStats(todayMinutes: 45, streakDays: 3, coins: 120, completedSessions: 7)
    }

    /// Ten minutes into 25, as the Live Activity samples are.
    static func running(now: Date) -> SessionEngine.Phase {
        .running(startedAt: now.addingTimeInterval(-600), endsAt: now.addingTimeInterval(900), plannedMinutes: 25)
    }

    /// Paused two minutes ago with 17 minutes to go.
    static func paused(now: Date) -> SessionEngine.Phase {
        .paused(
            startedAt: now.addingTimeInterval(-600),
            endsAt: now.addingTimeInterval(900),
            pausedAt: now.addingTimeInterval(-120),
            plannedMinutes: 25
        )
    }

    /// 25 minutes, done: 25 coins and 5 for finishing.
    static func finished(now: Date) -> SessionEngine.Phase {
        .finished(
            SessionRecord(
                id: "snapshot",
                startedAt: now.addingTimeInterval(-1_500),
                endedAt: now,
                plannedMinutes: 25,
                focusedSeconds: 1_500,
                completed: true,
                coinsEarned: 30
            )
        )
    }
}

/// Owns one shot's preview models, so a redraw never makes new ones.
private struct PreviewModels<Content: View>: View {
    @StateObject private var engine: SessionEngine
    @StateObject private var plus: PlusStore
    private let content: (SessionEngine, PlusStore) -> Content

    init(
        phase: SessionEngine.Phase = .idle,
        stats: FocusStats,
        liveActivityProblem: LiveActivityError? = nil,
        isPlus: Bool = false,
        @ViewBuilder content: @escaping (SessionEngine, PlusStore) -> Content
    ) {
        _engine = StateObject(wrappedValue: SessionEngine.preview(
            phase: phase,
            stats: stats,
            avatar: SampleLocklings.you,
            liveActivityProblem: liveActivityProblem
        ))
        _plus = StateObject(wrappedValue: PlusStore.preview(isPlus: isPlus))
        self.content = content
    }

    var body: some View {
        content(engine, plus)
    }
}

struct SnapshotHost: View {
    let mode: SnapshotMode
    @StateObject private var stepper = SnapshotStepper()

    var body: some View {
        let shot = mode.shots[min(stepper.index, mode.shots.count - 1)]
        Group {
            if let view = SnapshotGallery.view(for: shot.route, now: mode.referenceDate) {
                view
            } else {
                ContentUnavailableView(
                    "Unknown snapshot route",
                    systemImage: "questionmark.square.dashed",
                    description: Text(verbatim: shot.route)
                )
            }
        }
        // A fresh screen for every shot: no state carries over from the last one.
        .id(stepper.index)
        // The exporter waits for this marker before it captures, so it never photographs the
        // last screen while this one is still on its way (CI once caught nine stale shots in a
        // row). Invisible, and only ever in snapshot mode.
        .overlay(alignment: .topLeading) {
            Text(verbatim: String(stepper.index))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .accessibilityIdentifier("lk.snapshot.\(stepper.index)")
        }
        .preferredColorScheme(shot.appearance?.colorScheme)
        .onAppear {
            // Screens settle at once, so a capture never catches one mid-transition.
            UIView.setAnimationsEnabled(false)
        }
    }
}

/// Steps to the next shot when the exporter says so (a Darwin notification, which crosses from
/// the test runner's process into the app's inside the simulator).
@MainActor
final class SnapshotStepper: ObservableObject {
    @Published private(set) var index = 0

    init() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            snapshotStepperNext,
            SnapshotMode.nextNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    fileprivate func advance() {
        index += 1
    }
}

/// The Darwin notification callback: a plain function, so it can be a C function pointer. It may
/// run on any thread, so it hops to the main actor before touching the stepper.
private func snapshotStepperNext(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let stepper = Unmanaged<SnapshotStepper>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in stepper.advance() }
}
