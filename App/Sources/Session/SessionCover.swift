import Model
import Paywall
import SessionEngine
import SwiftUI

/// Everything shown over Home while a session exists: the timer while it runs or is paused, then
/// the celebration once it's finished. One full-screen cover for both, so finishing swaps the
/// screen in place instead of dismissing one cover and presenting another.
struct SessionCover: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore

    /// The phase on screen. It follows the engine's, except that it never becomes `.idle`: the
    /// last screen stays while the cover slides away.
    @State private var shown: SessionEngine.Phase
    @State private var showsPaywall = false

    init(engine: SessionEngine, plus: PlusStore) {
        self.engine = engine
        self.plus = plus
        _shown = State(initialValue: engine.phase)
    }

    var body: some View {
        content
            .animation(.smooth, value: shown)
            .onChange(of: engine.phase) { _, phase in
                if phase != .idle {
                    shown = phase
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .lockinPaywall(isPresented: $showsPaywall, store: plus, avatar: engine.avatar)
    }

    @ViewBuilder
    private var content: some View {
        switch shown {
        case .idle:
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        case .running, .paused:
            if let clock = SessionClock(shown) {
                SessionScreen(engine: engine, clock: clock)
                    .transition(.opacity)
            }
        case .finished(let record):
            FinishedScreen(
                record: record,
                avatar: engine.avatar,
                // The first session ever finished: the moment to mention friends (SPEC.md §1.1).
                offersFriends: record.completed && engine.stats.completedSessions == 1,
                onPlus: { showsPaywall = true },
                onDone: { engine.dismissFinished() }
            )
            .transition(.opacity)
        }
    }
}

/// A running or paused session's times, read from the engine's phase.
struct SessionClock: Equatable {
    let startedAt: Date
    let endsAt: Date
    /// Set while paused. The time left is then frozen at `endsAt - pausedAt`.
    let pausedAt: Date?
    let plannedMinutes: Int

    var isPaused: Bool {
        pausedAt != nil
    }

    var total: TimeInterval {
        TimeInterval(max(plannedMinutes, 1) * 60)
    }

    /// For `Text(timerInterval:)`, which traps on a backwards range.
    var timerRange: ClosedRange<Date> {
        min(startedAt, endsAt)...endsAt
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(pausedAt ?? now))
    }

    /// 0 at the start, 1 when the time's up.
    func progress(at now: Date) -> Double {
        min(1, max(0, 1 - remaining(at: now) / total))
    }

    /// Whole minutes focused so far: what ending now pays (a coin a minute).
    func focusedMinutes(at now: Date) -> Int {
        Int(max(0, total - remaining(at: now)) / 60)
    }
}

extension SessionClock {
    /// Nil unless the session is running or paused.
    init?(_ phase: SessionEngine.Phase) {
        switch phase {
        case let .running(startedAt, endsAt, plannedMinutes):
            self.init(startedAt: startedAt, endsAt: endsAt, pausedAt: nil, plannedMinutes: plannedMinutes)
        case let .paused(startedAt, endsAt, pausedAt, plannedMinutes):
            self.init(startedAt: startedAt, endsAt: endsAt, pausedAt: pausedAt, plannedMinutes: plannedMinutes)
        case .idle, .finished:
            return nil
        }
    }
}
