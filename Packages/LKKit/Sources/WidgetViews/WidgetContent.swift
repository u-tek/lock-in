import Foundation
import Model

/// What the Squad pet widget shows: a squad's pet, or, signed out or squadless, you.
public enum PetWidgetContent: Hashable, Sendable {
    case squad(WidgetData.Squad)
    /// No squad to show: your Lockling, your own streak and today's minutes. Most people start
    /// here (SPEC.md §1.1), so it has to be worth a place on the Home Screen on its own.
    case solo(avatar: AvatarCode, streak: Int, todayMinutes: Int)

    /// The squad picked in the widget's settings; if there's none, or you've left it, your first
    /// squad; with no squads, you.
    public init(data: WidgetData, squadID: String?) {
        if let squadID, let squad = data.squad(id: squadID) {
            self = .squad(squad)
        } else if let first = data.squads.first {
            self = .squad(first)
        } else {
            self = .solo(avatar: data.avatarCode, streak: data.soloStreak, todayMinutes: data.todayMinutes)
        }
    }

    /// Where a tap goes: Home with the squad picked. Solo, the app as it was.
    public var url: URL? {
        switch self {
        case .squad(let squad): WidgetLink.squad(squad.id)
        case .solo: nil
        }
    }
}

/// What the Lock in widget shows at a moment.
public enum LockInWidgetState: Hashable, Sendable {
    /// No session: the Lock in button, and today's minutes.
    case idle(todayMinutes: Int)
    /// Counting down to `ends`.
    case running(ends: Date, squadName: String?)
    /// Stopped with `remaining` seconds to go.
    case paused(remaining: TimeInterval, squadName: String?)

    /// The session in `data` as it stands at `now`. One whose time has run out reads as idle
    /// before the app gets round to writing that it's over.
    public init(data: WidgetData, now: Date) {
        guard let session = data.session, session.isOngoing(at: now) else {
            self = .idle(todayMinutes: data.todayMinutes)
            return
        }
        if session.isPaused {
            self = .paused(remaining: session.remaining(at: now), squadName: session.squadName)
        } else {
            self = .running(ends: session.endDate, squadName: session.squadName)
        }
    }
}

/// Made-up data for the widget gallery's previews, placeholders, and the app's `widgets.*`
/// snapshots.
public enum WidgetSamples {
    /// A free-parts Lockling.
    public static let avatar = AvatarCode(body: 0, colour: 2, eyes: 1, hat: 1)

    /// A squad four days into a streak, with a happy teen sprout and two locked in now.
    public static let squad = WidgetData.Squad(
        id: "sqLibGob01",
        name: "Library Goblins",
        pet: "sprout.2",
        mood: 3,
        progress: 0.42,
        streak: 4,
        countedToday: true,
        lockedIn: 2
    )

    /// A new squad whose egg hasn't hatched, nobody in yet today.
    public static let newSquad = WidgetData.Squad(
        id: "sqNightOw1",
        name: "Night Owls",
        pet: "ember.0",
        mood: 1,
        progress: 0,
        streak: 0,
        countedToday: false,
        lockedIn: 0
    )

    /// In a squad (or two), nothing running.
    public static func squads(avatar: AvatarCode = WidgetSamples.avatar, now: Date = Date()) -> WidgetData {
        WidgetData(
            avatar: avatar.code,
            todayMinutes: 45,
            soloStreak: 3,
            squads: [squad, newSquad],
            session: nil,
            updatedAt: now.timeIntervalSince1970
        )
    }

    /// No squads: the solo fallback.
    public static func solo(avatar: AvatarCode = WidgetSamples.avatar, now: Date = Date()) -> WidgetData {
        WidgetData(
            avatar: avatar.code,
            todayMinutes: 45,
            soloStreak: 3,
            squads: [],
            session: nil,
            updatedAt: now.timeIntervalSince1970
        )
    }

    /// Ten minutes into 25, solo.
    public static func running(avatar: AvatarCode = WidgetSamples.avatar, now: Date = Date()) -> WidgetData {
        var data = solo(avatar: avatar, now: now)
        data.session = WidgetData.Session(endsAt: now.addingTimeInterval(15 * 60).timeIntervalSince1970)
        return data
    }

    /// Paused with 17 minutes to go, in a squad's room.
    public static func paused(avatar: AvatarCode = WidgetSamples.avatar, now: Date = Date()) -> WidgetData {
        var data = squads(avatar: avatar, now: now)
        data.session = WidgetData.Session(
            endsAt: now.addingTimeInterval(17 * 60).timeIntervalSince1970,
            pausedAt: now.timeIntervalSince1970,
            squadName: squad.name
        )
        return data
    }
}
