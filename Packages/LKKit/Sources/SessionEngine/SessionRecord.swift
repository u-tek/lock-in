import Foundation

/// One finished session, completed or ended early. Kept in the session store's history.
public struct SessionRecord: Codable, Hashable, Sendable, Identifiable {
    /// The session's short id, the same `sid` its Live Activity carried.
    public let id: String
    public let startedAt: Date
    /// When the timer ran out for a completed session (even if the app only noticed later), or
    /// when it was ended early.
    public let endedAt: Date
    public let plannedMinutes: Int
    /// Time on the clock, pauses left out.
    public let focusedSeconds: Int
    public let completed: Bool
    public let coinsEarned: Int

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        plannedMinutes: Int,
        focusedSeconds: Int,
        completed: Bool,
        coinsEarned: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.focusedSeconds = focusedSeconds
        self.completed = completed
        self.coinsEarned = coinsEarned
    }

    /// Whole minutes focused, rounded down.
    public var focusedMinutes: Int {
        focusedSeconds / 60
    }

    /// Coins on top of the minutes for seeing a session through.
    public static let completionBonus = 5

    /// One coin per whole focused minute, and the bonus for finishing (M1.md).
    static func coins(focusedSeconds: Int, completed: Bool) -> Int {
        max(0, focusedSeconds) / 60 + (completed ? completionBonus : 0)
    }
}

/// The numbers on Home: today's minutes, the streak, coins and sessions finished.
public struct FocusStats: Codable, Equatable, Sendable {
    public var todayMinutes: Int
    public var streakDays: Int
    public var coins: Int
    public var completedSessions: Int

    public init(todayMinutes: Int = 0, streakDays: Int = 0, coins: Int = 0, completedSessions: Int = 0) {
        self.todayMinutes = todayMinutes
        self.streakDays = streakDays
        self.coins = coins
        self.completedSessions = completedSessions
    }

    public static let zero = FocusStats()

    /// A day keeps the streak going with this many focused minutes: the squad rule of SPEC.md
    /// §1.2 (a session of at least 20 minutes), applied to one person.
    public static let streakMinimumMinutes = 20

    /// Works the stats out from the history.
    ///
    /// A session's minutes belong to the local day it ended on, for today's total and the streak
    /// alike: a session that runs past midnight counts for the day it was finished, which is the
    /// day the person saw it finish. The streak counts back from today, or from yesterday while
    /// today hasn't reached the minimum yet, so it doesn't read 0 every morning.
    static func compute(
        history: [SessionRecord],
        coins: Int,
        completedSessions: Int,
        now: Date,
        calendar: Calendar
    ) -> FocusStats {
        var secondsByDay: [Date: Int] = [:]
        for record in history {
            secondsByDay[calendar.startOfDay(for: record.endedAt), default: 0] += max(0, record.focusedSeconds)
        }
        func previousDay(_ day: Date) -> Date? {
            // Back to the start of the day again: where midnight doesn't exist (a DST change at
            // 00:00), the day starts at 01:00 and one day earlier would land mid-morning.
            calendar.date(byAdding: .day, value: -1, to: day).map { calendar.startOfDay(for: $0) }
        }

        let minimum = streakMinimumMinutes * 60
        let today = calendar.startOfDay(for: now)
        let todaySeconds = secondsByDay[today] ?? 0
        var day: Date? = todaySeconds >= minimum ? today : previousDay(today)
        var streak = 0
        while let current = day, (secondsByDay[current] ?? 0) >= minimum {
            streak += 1
            day = previousDay(current)
        }
        return FocusStats(
            todayMinutes: todaySeconds / 60,
            streakDays: streak,
            coins: coins,
            completedSessions: completedSessions
        )
    }
}
