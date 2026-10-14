import API
import Combine
import Core
import Foundation
import Model
import SessionEngine
import Social
import WidgetKit

/// Keeps what the widgets show (`WidgetData` in the App Group) in step with the app: your Lockling,
/// today's minutes and streak, your squads and their pets, and the session running now
/// (docs/milestones/M6.md). Whenever any of it changes, the file is rewritten and every widget's
/// timeline reloaded; when nothing a widget shows has changed, nothing is written.
///
/// It watches the models rather than the screens, because the Lock in widget and the Control
/// Center control start sessions in a background launch with no screen: the engine's change is
/// written before the intent returns.
@MainActor
final class WidgetDataWriter {
    private let store: WidgetDataStore
    private let now: () -> Date
    /// What's in the file, so an unchanged state isn't written (or reloaded) again.
    private var written: WidgetData?
    private var subscription: AnyCancellable?
    /// The streak and recap reminders, planned from what the widgets show (M6).
    let reminders = ReminderScheduler()

    init(store: WidgetDataStore = .appGroup(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        written = store.load()
    }

    /// Writes now, then on every change for as long as the writer lives.
    ///
    /// `@Published` sends a new value before the property holds it, so the data is built from the
    /// values sent, never read back from the models.
    func watch(engine: SessionEngine, social: SocialModels) {
        reminders.watch(engine: engine, social: social)
        let session = Publishers.CombineLatest4(engine.$phase, engine.$stats, engine.$avatar, engine.$mode)
        let squads = Publishers.CombineLatest3(
            social.squads.$squads,
            social.rooms.$lockedIn,
            social.account.$state.map(\.isSignedIn).removeDuplicates()
        )
        subscription = session.combineLatest(squads)
            .sink { [weak self] engineValues, socialValues in
                guard let self else { return }
                let (phase, stats, avatar, mode) = engineValues
                let (squads, counts, isSignedIn) = socialValues
                self.write(WidgetData(
                    phase: phase,
                    stats: stats,
                    avatar: avatar,
                    mode: mode,
                    squads: isSignedIn ? squads : [],
                    roomCounts: counts,
                    now: self.now()
                ))
            }
    }

    private func write(_ data: WidgetData) {
        // Then the reminders, written or not: the first state of a launch, or of a new day, can
        // change them without changing the file.
        defer { reminders.update(for: data) }
        if let written, written.hasSameContent(as: data) {
            return
        }
        guard store.save(data) else { return }
        written = data
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// Inside these extensions `Squad` is `WidgetData.Squad`: the server's is `API.Squad`.

extension WidgetData {
    /// The widgets' view of the app at `now`. Signed out, pass no squads: the last account's may
    /// still be in memory.
    init(
        phase: SessionEngine.Phase,
        stats: FocusStats,
        avatar: AvatarCode,
        mode: SessionMode,
        squads: [API.Squad],
        roomCounts: [String: Int],
        now: Date
    ) {
        let squadName = mode.squadId.flatMap { id in squads.first { $0.id == id }?.name }
        let session: Session?
        switch phase {
        case .running(_, let endsAt, _):
            session = Session(endsAt: endsAt.timeIntervalSince1970, squadName: squadName)
        case .paused(_, let endsAt, let pausedAt, _):
            session = Session(endsAt: endsAt.timeIntervalSince1970, pausedAt: pausedAt.timeIntervalSince1970, squadName: squadName)
        case .idle, .finished:
            session = nil
        }
        self.init(
            avatar: avatar.code,
            todayMinutes: stats.todayMinutes,
            soloStreak: stats.streakDays,
            squads: squads.map { squad in
                WidgetData.Squad(squad, lockedIn: squad.openSessionId.flatMap { roomCounts[$0] })
            },
            session: session,
            updatedAt: now.timeIntervalSince1970
        )
    }
}

extension WidgetData.Squad {
    /// A squad as `GET /squads` has it.
    ///
    /// The pet's species, stage, mood and progress, and the squad's streak, are the server's
    /// (docs/milestones/M5.md; an egg is stage 0 and carries its species for its colour). From a
    /// server older than M5 the pet reads as content, its progress comes from its XP and the streak
    /// is 0, which the widgets leave unsaid rather than showing "No streak".
    ///
    /// - Parameter lockedIn: How many are in the squad's open room, when it could be read. An open
    ///   room it couldn't read has at least one.
    init(_ squad: API.Squad, lockedIn: Int?) {
        let pet = squad.pet
        // Read leniently, like a pushed `Pet.k`: a species this version can't draw still reads.
        // A boosted squad's pet wears its accessory on the widgets too (M7).
        let code = pet.code
        self.init(
            id: squad.id,
            name: squad.name,
            pet: code.code,
            mood: pet.petMood.rawValue,
            progress: pet.clampedProgress,
            streak: max(0, squad.streak.count),
            countedToday: squad.streak.countedToday,
            lockedIn: lockedIn ?? (squad.isLive ? 1 : 0)
        )
    }
}
