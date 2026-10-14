import Foundation
import Model

// The two local reminders (SPEC.md §5.7, docs/milestones/M6.md): what to schedule, worked out from
// what the widgets show (`WidgetData`), the settings, quiet hours, the day's limit and the clock.
// Plain values only, so every rule is unit-tested; the app schedules what comes out
// (`UNUserNotificationCenter`) whenever the widgets' data is written, and when the settings change.

/// Which reminder.
public enum ReminderKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// "Streak at risk": once a day at the time you picked.
    case streak
    /// "Weekly recap": Monday at 09:00.
    case recap
}

/// One reminder to schedule: a local notification at `fireDate` saying `body`.
public struct PlannedReminder: Hashable, Sendable {
    public var kind: ReminderKind
    public var fireDate: Date
    public var body: String
    /// The notification request's identifier: `lk.reminder.<kind>.<YYYY-MM-DD>`, one per kind a
    /// day. Every reminder's starts with `ReminderPlanner.identifierPrefix`.
    public var identifier: String

    public init(kind: ReminderKind, fireDate: Date, body: String, identifier: String) {
        self.kind = kind
        self.fireDate = fireDate
        self.body = body
        self.identifier = identifier
    }
}

/// When the next weekly recap comes, and the week it sums up.
public struct RecapSlot: Hashable, Sendable {
    public var fireDate: Date
    /// Monday 00:00 a week before `fireDate`'s Monday, up to (not including) that Monday 00:00.
    public var week: DateInterval

    public init(fireDate: Date, week: DateInterval) {
        self.fireDate = fireDate
        self.week = week
    }
}

/// Where you came in one of your squads' weekly leaderboards, the last one the app saw.
public struct SquadPlace: Hashable, Sendable {
    public var squadName: String
    /// 1 for the most minutes.
    public var place: Int
    /// Everyone on the leaderboard.
    public var of: Int
    /// The leaderboard's week, in the squad's time zone.
    public var week: DateInterval

    public init(squadName: String, place: Int, of: Int, week: DateInterval) {
        self.squadName = squadName
        self.place = place
        self.of = of
        self.week = week
    }
}

/// What the weekly recap says, worked out by the app for `slot`'s week: your minutes from the
/// sessions you finished on this phone, and your place in a squad if the app saw that week's
/// leaderboard.
public struct RecapFacts: Hashable, Sendable {
    public var slot: RecapSlot
    public var minutes: Int
    public var place: SquadPlace?

    public init(slot: RecapSlot, minutes: Int, place: SquadPlace? = nil) {
        self.slot = slot
        self.minutes = minutes
        self.place = place
    }
}

public enum ReminderPlanner {
    /// Every reminder's request identifier starts with this, so the app can take back the ones it
    /// scheduled without touching anything else.
    public static let identifierPrefix = "lk.reminder."
    /// Monday, in `Calendar`'s weekday numbering (1 is Sunday).
    public static let recapWeekday = 2
    /// 09:00.
    public static let recapTime = 9 * 60
    /// A reminder whose time falls in quiet hours comes this many minutes before they start.
    public static let quietHoursLead = 15
    /// Streak reminders are planned for today and tomorrow: the day after, a streak that wasn't
    /// counted has broken anyway (`WidgetData.asSeen(at:calendar:)`), and the app will have
    /// planned again by then if it's been opened.
    static let streakDays = 2

    // MARK: - The plan

    /// The reminders to schedule at `now`, soonest first. Everything already scheduled is replaced
    /// by these.
    ///
    /// - Streak at risk, today and tomorrow at `settings.streakTime` (moved out of quiet hours):
    ///   only when, as the data will read then, you've focused under the 20 minutes that count a
    ///   day, no session is running, and one of your squads with a streak hasn't counted that day
    ///   (the longest such streak is named). With no squad at risk, your own streak, if you have
    ///   one. Never at a time that's passed.
    /// - Weekly recap, at `recap.slot`, when there were minutes to recap.
    /// - At most `ReminderLog.dailyLimit` a day, counting what `log` says was already delivered
    ///   that day; the streak reminder comes first.
    ///
    /// - Parameter recap: The next recap and what it says (`recapSlot(after:quietHours:calendar:)`
    ///   for when); nil when it's switched off.
    public static func plan(
        data: WidgetData,
        settings: ReminderSettings,
        quietHours: QuietHours,
        log: ReminderLog,
        recap: RecapFacts?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlannedReminder] {
        var candidates: [PlannedReminder] = []
        if settings.streakEnabled {
            candidates += streakReminders(data: data, settings: settings, quietHours: quietHours, now: now, calendar: calendar)
        }
        if settings.recapEnabled, let recap, let reminder = recapReminder(recap, now: now, calendar: calendar) {
            candidates.append(reminder)
        }

        var planned: [PlannedReminder] = []
        for candidate in candidates {
            let sameDay = planned.filter { calendar.isDate($0.fireDate, inSameDayAs: candidate.fireDate) }.count
            let delivered = log.delivered(onDayOf: candidate.fireDate, before: now, calendar: calendar)
            if sameDay + delivered < ReminderLog.dailyLimit {
                planned.append(candidate)
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// Streak reminders for today and tomorrow, before the day's limit.
    static func streakReminders(
        data: WidgetData,
        settings: ReminderSettings,
        quietHours: QuietHours,
        now: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard let minute = deliveryMinute(settings.streakTime, quietHours: quietHours) else { return [] }
        let today = calendar.startOfDay(for: now)
        var reminders: [PlannedReminder] = []
        for offset in 0..<streakDays {
            guard let next = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let day = calendar.startOfDay(for: next)
            let fireDate = QuietHours.date(minutes: minute, on: day, calendar: calendar)
            guard fireDate > now else { continue }
            // What the widgets will say then: a later day starts with nothing counted.
            let seen = data.asSeen(at: fireDate, calendar: calendar)
            if let session = seen.session, session.isOngoing(at: fireDate) {
                continue
            }
            guard seen.todayMinutes < WidgetData.soloStreakMinutes, let body = streakMessage(for: seen) else { continue }
            reminders.append(PlannedReminder(
                kind: .streak,
                fireDate: fireDate,
                body: body,
                identifier: identifier(.streak, on: fireDate, calendar: calendar)
            ))
        }
        return reminders
    }

    /// "Library Goblins' 6-day streak needs you today 🔥": the longest streak among your squads
    /// that haven't counted today, else your own. Nil when no streak is at risk.
    static func streakMessage(for data: WidgetData) -> String? {
        let atRisk = data.squads.filter { !$0.countedToday && $0.streak > 0 }
        // The first of the longest: `max(by:)` keeps the earliest of equals.
        if let squad = atRisk.max(by: { $0.streak < $1.streak }) {
            return "\(possessive(squad.name)) \(streakPhrase(squad.streak)) needs you today 🔥"
        }
        if data.soloStreak > 0 {
            return "Your \(streakPhrase(data.soloStreak)) needs you today 🔥"
        }
        return nil
    }

    /// "6-day streak", or just "streak" for one day.
    static func streakPhrase(_ days: Int) -> String {
        days > 1 ? "\(days)-day streak" : "streak"
    }

    // MARK: - Weekly recap

    /// The next Monday 09:00 (moved out of quiet hours) after `now`, and the week before it. Nil
    /// when quiet hours leave no time on a Monday morning or evening for it.
    public static func recapSlot(after now: Date, quietHours: QuietHours, calendar: Calendar = .autoupdatingCurrent) -> RecapSlot? {
        guard let minute = deliveryMinute(recapTime, quietHours: quietHours) else { return nil }
        let today = calendar.startOfDay(for: now)
        // Today if it's Monday and the time's still ahead, otherwise one of the next seven days.
        for offset in 0...7 {
            guard let next = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let day = calendar.startOfDay(for: next)
            guard calendar.component(.weekday, from: day) == recapWeekday else { continue }
            let fireDate = QuietHours.date(minutes: minute, on: day, calendar: calendar)
            guard fireDate > now,
                  let weekBefore = calendar.date(byAdding: .day, value: -7, to: day)
            else { continue }
            let start = calendar.startOfDay(for: weekBefore)
            guard start < day else { continue }
            return RecapSlot(fireDate: fireDate, week: DateInterval(start: start, end: day))
        }
        return nil
    }

    /// The recap for `facts`, or nil when there's nothing to recap or its time has passed.
    static func recapReminder(_ facts: RecapFacts, now: Date, calendar: Calendar) -> PlannedReminder? {
        guard facts.minutes > 0, facts.slot.fireDate > now else { return nil }
        return PlannedReminder(
            kind: .recap,
            fireDate: facts.slot.fireDate,
            body: recapMessage(minutes: facts.minutes, place: place(facts.place, in: facts.slot.week)),
            identifier: identifier(.recap, on: facts.slot.fireDate, calendar: calendar)
        )
    }

    /// "Last week: 6 h 20 m locked in." and, with a place, " You came 2nd in Library Goblins."
    static func recapMessage(minutes: Int, place: SquadPlace?) -> String {
        var message = "Last week: \(duration(minutes: minutes)) locked in."
        if let place {
            message += " You came \(ordinal(place.place)) in \(place.squadName)."
        }
        return message
    }

    /// The place, if its leaderboard is the recap's week (the middle of the leaderboard's week,
    /// which runs in the squad's time zone, falls in the recap's local one) and there was
    /// someone to come ahead of or behind.
    public static func place(_ place: SquadPlace?, in week: DateInterval) -> SquadPlace? {
        guard let place, place.place >= 1, place.of >= 2, place.place <= place.of else { return nil }
        let middle = place.week.start.addingTimeInterval(place.week.duration / 2)
        return middle >= week.start && middle < week.end ? place : nil
    }

    /// "45 m", "2 h", "6 h 20 m".
    static func duration(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) m"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) m"
        }
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "21st".
    static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 10, number % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }

    // MARK: - Quiet hours

    /// When a reminder wanted at `minute` after midnight comes, in minutes after midnight: then,
    /// unless that's in quiet hours. In quiet hours that began that evening, `quietHoursLead`
    /// minutes before they start; in quiet hours that began the night before, when they end. Nil
    /// when neither is a time that day outside quiet hours.
    public static func deliveryMinute(_ minute: Int, quietHours: QuietHours) -> Int? {
        let wanted = QuietHours.normalised(minute)
        guard let window = quietHours.window, quietHours.contains(minute: wanted) else { return wanted }
        if wanted >= window.start {
            let before = window.start - quietHoursLead
            if before >= 0, !quietHours.contains(minute: before) {
                return before
            }
        }
        if window.end > wanted, !quietHours.contains(minute: window.end) {
            return window.end
        }
        return nil
    }

    // MARK: - Words and ids

    /// "Library Goblins'", "Night Owl's".
    static func possessive(_ name: String) -> String {
        name.hasSuffix("s") || name.hasSuffix("S") ? "\(name)'" : "\(name)'s"
    }

    /// `lk.reminder.streak.2027-01-15`.
    static func identifier(_ kind: ReminderKind, on date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = [padded(parts.year ?? 0, to: 4), padded(parts.month ?? 0, to: 2), padded(parts.day ?? 0, to: 2)]
            .joined(separator: "-")
        return "\(identifierPrefix)\(kind.rawValue).\(day)"
    }

    /// `number` with leading zeros up to `width` digits.
    private static func padded(_ number: Int, to width: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
