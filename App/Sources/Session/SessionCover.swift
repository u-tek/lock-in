import Foundation
import Model
import Paywall
import SessionEngine
import Social
import SwiftUI

/// Everything shown over Home while a session exists: the timer while it runs or is paused, then
/// the celebration once it's finished. One full-screen cover for both, so finishing swaps the
/// screen in place instead of dismissing one cover and presenting another.
struct SessionCover: View {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var plus: PlusStore
    @ObservedObject var squads: SquadsStore
    let social: SocialModels
    /// Snapshots: a squad room the preview engine can't hold, and a cheer picker already open.
    private let squadPreview: SquadSessionInfo?
    private let cheeringPreview: String?

    /// The phase on screen. It follows the engine's, except that it never becomes `.idle`: the
    /// last screen stays while the cover slides away.
    @State private var shown: SessionEngine.Phase
    @State private var showsFriends = false
    @State private var showsPaywall = false
    /// The session on screen is a squad's. Set while it runs and kept through its finish, which
    /// the engine may already have moved on from.
    @State private var isSquad: Bool
    /// The first squad session ever completed here: Lockin Plus's moment (SPEC.md §2, paywall
    /// moment 1).
    @State private var offersPlus: Bool

    /// - Parameters:
    ///   - squad: the room to show (snapshots); otherwise the engine's.
    ///   - cheering: a squadmate whose cheer picker is open (snapshots).
    ///   - firstSquadFinish: show the finish as the first squad session's (snapshots).
    init(
        engine: SessionEngine,
        plus: PlusStore,
        social: SocialModels,
        squad: SquadSessionInfo? = nil,
        cheering: String? = nil,
        firstSquadFinish: Bool = false
    ) {
        self.engine = engine
        self.plus = plus
        self.squads = social.squads
        self.social = social
        squadPreview = squad
        cheeringPreview = cheering
        _shown = State(initialValue: engine.phase)
        _isSquad = State(initialValue: engine.mode != .solo || squad != nil || firstSquadFinish)
        _offersPlus = State(initialValue: firstSquadFinish)
    }

    var body: some View {
        content
            .animation(.smooth, value: shown)
            .onChange(of: engine.phase) { _, phase in
                if phase != .idle {
                    shown = phase
                }
                noteChange(to: phase)
            }
            .onChange(of: engine.mode) { _, mode in
                if mode != .solo {
                    isSquad = true
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .sheet(isPresented: $showsFriends) {
                FriendsFlow(social: social, plus: plus, avatar: engine.avatar)
            }
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
                SessionScreen(engine: engine, clock: clock, squad: squad, cheering: cheeringPreview)
                    .transition(.opacity)
            }
        case .finished(let record):
            FinishedScreen(
                record: record,
                avatar: engine.avatar,
                // The first session ever finished: the moment to mention friends (SPEC.md §1.1).
                // Not after a squad's: those friends are here already.
                offersFriends: record.completed && engine.stats.completedSessions == 1 && !isSquad,
                onFriends: { showsFriends = true },
                offersPlus: offersPlus,
                onPlus: { showsPaywall = true },
                onDone: { engine.dismissFinished() }
            )
            .transition(.opacity)
        }
    }

    /// The squad room on screen: the snapshot's, or the engine's in a squad session.
    private var squad: SquadSessionInfo? {
        if let squadPreview {
            return squadPreview
        }
        guard case .squad(let squadID, _) = engine.mode, let room = engine.room else { return nil }
        let name = squads.squads.first { $0.id == squadID }?.name
        return SquadSessionInfo(name: name, room: room, me: engine.me)
    }

    private func noteChange(to phase: SessionEngine.Phase) {
        switch phase {
        case .running, .paused:
            // A new session can start from the finish screen (a widget, say): it's whatever the
            // engine says now.
            isSquad = engine.mode != .solo
        case .finished(let record):
            if record.completed, isSquad, !plus.isPlus {
                offersPlus = PlusMoments.claimFirstSquadFinish()
            }
        case .idle:
            break
        }
    }
}

/// Paywall moments that come once per install (SPEC.md §2).
enum PlusMoments {
    static let firstSquadFinishKey = "LKPlusMomentFirstSquadFinish"

    /// True the first time a squad session is completed here, false ever after.
    @MainActor
    static func claimFirstSquadFinish(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: firstSquadFinishKey) else { return false }
        defaults.set(true, forKey: firstSquadFinishKey)
        return true
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
