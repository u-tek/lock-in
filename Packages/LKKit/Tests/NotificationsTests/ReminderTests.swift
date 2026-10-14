import Foundation
import Model
import Testing
@testable import Notifications

/// Sydney, as in QuietHoursTests. 15 January 2027 is a Friday; the 18th is a Monday.
private let sydney: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
    return calendar
}()

/// A local time in Sydney.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15, month: Int = 1) -> Date {
    sydney.date(from: DateComponents(year: 2027, month: month, day: day, hour: hour, minute: minute))!
}

private func squad(_ name: String, streak: Int, counted: Bool, id: String? = nil) -> WidgetData.Squad {
    WidgetData.Squad(
        id: id ?? "sq\(name.prefix(6))",
        name: name,
        pet: "sprout.2",
        mood: 3,
        progress: 0.5,
        streak: streak,
        countedToday: counted,
        lockedIn: 0
    )
}

/// What the app wrote at `now`.
private func written(
    at now: Date,
    todayMinutes: Int = 0,
    soloStreak: Int = 0,
    squads: [WidgetData.Squad] = [],
    session: WidgetData.Session? = nil
) -> WidgetData {
    WidgetData(
        todayMinutes: todayMinutes,
        soloStreak: soloStreak,
        squads: squads,
        session: session,
        updatedAt: now.timeIntervalSince1970
    )
}

/// The plan with the default settings and quiet hours, no recap and nothing delivered yet.
private func plan(
    _ data: WidgetData,
    now: Date,
    settings: ReminderSettings = .default,
    quietHours: QuietHours = .default,
    log: ReminderLog = ReminderLog(),
    recap: RecapFacts? = nil
) -> [PlannedReminder] {
    ReminderPlanner.plan(
        data: data,
        settings: settings,
        quietHours: quietHours,
        log: log,
        recap: recap,
        now: now,
        calendar: sydney
    )
}

/// Defaults of their own for one test, emptied afterwards.
private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "ReminderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Suite struct StreakReminderTests {
    @Test func aSquadStreakAtRiskToday() throws {
        let now = at(12)
        let reminders = plan(written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)]), now: now)
        // Tomorrow it has broken, so today's is the only one.
        #expect(reminders.count == 1)
        let reminder = try #require(reminders.first)
        #expect(reminder.kind == .streak)
        #expect(reminder.fireDate == at(19))
        #expect(reminder.body == "Library Goblins' 6-day streak needs you today 🔥")
        #expect(reminder.identifier == "lk.reminder.streak.2027-01-15")
    }

    @Test func aDayThatCountsMovesItToTomorrow() {
        // Counted today, so the streak is alive tomorrow, and tomorrow hasn't counted yet.
        let now = at(12)
        let data = written(at: now, todayMinutes: 25, squads: [squad("Library Goblins", streak: 6, counted: true)])
        let reminders = plan(data, now: now)
        #expect(reminders.map(\.fireDate) == [at(19, day: 16)])
        #expect(reminders.first?.body == "Library Goblins' 6-day streak needs you today 🔥")
        #expect(reminders.first?.identifier == "lk.reminder.streak.2027-01-16")
    }

    @Test func yourPartDoneIsEnoughForToday() {
        // You've focused 30 minutes; the squad hasn't counted. Nothing today. Tomorrow the squad's
        // streak has broken, but yours (counted today) is at risk.
        let now = at(12)
        let data = written(at: now, todayMinutes: 30, soloStreak: 4, squads: [squad("Library Goblins", streak: 6, counted: false)])
        let reminders = plan(data, now: now)
        #expect(reminders.map(\.fireDate) == [at(19, day: 16)])
        #expect(reminders.first?.body == "Your 4-day streak needs you today 🔥")
    }

    @Test func aFewMinutesDontCountTheDay() {
        let now = at(12)
        let data = written(at: now, todayMinutes: 12, squads: [squad("Library Goblins", streak: 6, counted: false)])
        #expect(plan(data, now: now).map(\.fireDate) == [at(19)])
    }

    @Test func noStreakNoReminder() {
        let now = at(12)
        #expect(plan(written(at: now), now: now).isEmpty)
        #expect(plan(written(at: now, squads: [squad("Night Owls", streak: 0, counted: false)]), now: now).isEmpty)
    }

    @Test func theLongestStreakAtRiskIsNamed() {
        let now = at(12)
        let squads = [
            squad("Library Goblins", streak: 10, counted: true),
            squad("Study Club", streak: 3, counted: false),
            squad("Night Owl", streak: 5, counted: false),
            squad("Late Crew", streak: 5, counted: false),
        ]
        let reminders = plan(written(at: now, squads: squads), now: now)
        #expect(reminders.first?.fireDate == at(19))
        #expect(reminders.first?.body == "Night Owl's 5-day streak needs you today 🔥")
    }

    @Test func aOneDayStreakIsJustAStreak() {
        let now = at(12)
        let reminders = plan(written(at: now, squads: [squad("Study Club", streak: 1, counted: false)]), now: now)
        #expect(reminders.first?.body == "Study Club's streak needs you today 🔥")
        let solo = plan(written(at: now, soloStreak: 1), now: now)
        #expect(solo.first?.body == "Your streak needs you today 🔥")
    }

    @Test func yourOwnStreakWhenNoSquadIsAtRisk() {
        // The squad counted today without you: your own streak is still at risk.
        let now = at(12)
        let data = written(at: now, soloStreak: 2, squads: [squad("Library Goblins", streak: 6, counted: true)])
        let reminders = plan(data, now: now)
        #expect(reminders.first?.fireDate == at(19))
        #expect(reminders.first?.body == "Your 2-day streak needs you today 🔥")
    }

    @Test func aTimeThatsPassedIsNotScheduled() {
        // 20:00: today's has gone, and by tomorrow the uncounted streak has broken.
        let now = at(20)
        #expect(plan(written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)]), now: now).isEmpty)
    }

    @Test func notDuringASession() {
        let now = at(18, 50)
        let atRisk = [squad("Library Goblins", streak: 6, counted: false)]
        let running = WidgetData.Session(endsAt: at(19, 5).timeIntervalSince1970)
        #expect(plan(written(at: now, squads: atRisk, session: running), now: now).isEmpty)
        let paused = WidgetData.Session(endsAt: at(19, 5).timeIntervalSince1970, pausedAt: now.timeIntervalSince1970)
        #expect(plan(written(at: now, squads: atRisk, session: paused), now: now).isEmpty)
        // Over by then: it comes.
        let short = WidgetData.Session(endsAt: at(18, 55).timeIntervalSince1970)
        #expect(plan(written(at: now, squads: atRisk, session: short), now: now).map(\.fireDate) == [at(19)])
    }

    @Test func switchedOff() {
        let now = at(12)
        var settings = ReminderSettings.default
        settings.streakEnabled = false
        #expect(plan(written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)]), now: now, settings: settings).isEmpty)
    }

    @Test func atTheTimeYouPicked() {
        let now = at(12)
        let settings = ReminderSettings(streakTime: 17 * 60 + 30)
        let reminders = plan(written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)]), now: now, settings: settings)
        #expect(reminders.map(\.fireDate) == [at(17, 30)])
    }

    @Test func quietHoursMoveIt() {
        let now = at(12)
        let atRisk = written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)])
        // 23:00 is in quiet hours (22:00 to 07:00): it comes at 21:45.
        let late = plan(atRisk, now: now, settings: ReminderSettings(streakTime: 23 * 60))
        #expect(late.map(\.fireDate) == [at(21, 45)])
        // Quiet hours off: 23:00.
        var off = QuietHours.default
        off.isEnabled = false
        #expect(plan(atRisk, now: now, settings: ReminderSettings(streakTime: 23 * 60), quietHours: off).map(\.fireDate) == [at(23)])
    }
}

@Suite struct DeliveryMinuteTests {
    @Test func outsideQuietHoursItsTheTimeAsked() {
        #expect(ReminderPlanner.deliveryMinute(19 * 60, quietHours: .default) == 19 * 60)
        #expect(ReminderPlanner.deliveryMinute(7 * 60, quietHours: .default) == 7 * 60)
        #expect(ReminderPlanner.deliveryMinute(21 * 60 + 59, quietHours: .default) == 21 * 60 + 59)
    }

    @Test func eveningQuietHoursComeJustBefore() {
        #expect(ReminderPlanner.deliveryMinute(22 * 60, quietHours: .default) == 21 * 60 + 45)
        #expect(ReminderPlanner.deliveryMinute(23 * 60 + 59, quietHours: .default) == 21 * 60 + 45)
    }

    @Test func morningQuietHoursWaitUntilTheyEnd() {
        #expect(ReminderPlanner.deliveryMinute(0, quietHours: .default) == 7 * 60)
        #expect(ReminderPlanner.deliveryMinute(6 * 60 + 59, quietHours: .default) == 7 * 60)
    }

    @Test func aWindowWithinTheDay() {
        let siesta = QuietHours(start: 13 * 60, end: 14 * 60 + 30)
        #expect(ReminderPlanner.deliveryMinute(13 * 60 + 30, quietHours: siesta) == 12 * 60 + 45)
        #expect(ReminderPlanner.deliveryMinute(15 * 60, quietHours: siesta) == 15 * 60)
        // From midnight: no time before it that day, so when it ends.
        let night = QuietHours(start: 0, end: 8 * 60)
        #expect(ReminderPlanner.deliveryMinute(60, quietHours: night) == 8 * 60)
    }

    @Test func offOrEmptyChangesNothing() {
        var off = QuietHours.default
        off.isEnabled = false
        #expect(ReminderPlanner.deliveryMinute(23 * 60, quietHours: off) == 23 * 60)
        #expect(ReminderPlanner.deliveryMinute(10 * 60, quietHours: QuietHours(start: 600, end: 600)) == 10 * 60)
    }

    @Test func minutesWrap() {
        #expect(ReminderPlanner.deliveryMinute(19 * 60 + 1_440, quietHours: .default) == 19 * 60)
        #expect(QuietHours.default.contains(minute: -60))
        #expect(!QuietHours.default.contains(minute: 12 * 60))
    }
}

@Suite struct RecapTests {
    @Test func theNextMondayMorning() throws {
        let slot = try #require(ReminderPlanner.recapSlot(after: at(12), quietHours: .default, calendar: sydney))
        #expect(slot.fireDate == at(9, day: 18))
        #expect(slot.week.start == at(0, day: 11))
        #expect(slot.week.end == at(0, day: 18))
    }

    @Test func mondayBeforeNineIsToday() throws {
        let early = try #require(ReminderPlanner.recapSlot(after: at(8, day: 18), quietHours: .default, calendar: sydney))
        #expect(early.fireDate == at(9, day: 18))
        let onTheDot = try #require(ReminderPlanner.recapSlot(after: at(9, day: 18), quietHours: .default, calendar: sydney))
        #expect(onTheDot.fireDate == at(9, day: 25))
        #expect(onTheDot.week.start == at(0, day: 18))
    }

    @Test func lateQuietHoursPushItBack() throws {
        let lieIn = QuietHours(start: 22 * 60, end: 10 * 60)
        let slot = try #require(ReminderPlanner.recapSlot(after: at(12), quietHours: lieIn, calendar: sydney))
        #expect(slot.fireDate == at(10, day: 18))
    }

    @Test func whatItSays() {
        #expect(ReminderPlanner.recapMessage(minutes: 380, place: nil) == "Last week: 6 h 20 m locked in.")
        #expect(ReminderPlanner.recapMessage(minutes: 45, place: nil) == "Last week: 45 m locked in.")
        #expect(ReminderPlanner.recapMessage(minutes: 120, place: nil) == "Last week: 2 h locked in.")
        let week = DateInterval(start: at(0, day: 11), end: at(0, day: 18))
        let second = SquadPlace(squadName: "Library Goblins", place: 2, of: 4, week: week)
        #expect(ReminderPlanner.recapMessage(minutes: 380, place: second) == "Last week: 6 h 20 m locked in. You came 2nd in Library Goblins.")
    }

    @Test func plannedWithThePlaceFromThatWeek() throws {
        let now = at(12)
        let slot = try #require(ReminderPlanner.recapSlot(after: now, quietHours: .default, calendar: sydney))
        // The squad's week runs in London: Monday 00:00 there is 11:00 in Sydney.
        let london = DateInterval(start: at(11, day: 11), end: at(11, day: 18))
        let place = SquadPlace(squadName: "Library Goblins", place: 2, of: 4, week: london)
        let reminders = plan(written(at: now), now: now, recap: RecapFacts(slot: slot, minutes: 380, place: place))
        #expect(reminders.count == 1)
        #expect(reminders.first?.kind == .recap)
        #expect(reminders.first?.fireDate == at(9, day: 18))
        #expect(reminders.first?.body == "Last week: 6 h 20 m locked in. You came 2nd in Library Goblins.")
        #expect(reminders.first?.identifier == "lk.reminder.recap.2027-01-18")
    }

    @Test func anOldLeaderboardIsLeftOut() throws {
        let now = at(12)
        let slot = try #require(ReminderPlanner.recapSlot(after: now, quietHours: .default, calendar: sydney))
        let weekBefore = DateInterval(start: at(0, day: 4), end: at(0, day: 11))
        let stale = SquadPlace(squadName: "Library Goblins", place: 1, of: 4, week: weekBefore)
        let reminders = plan(written(at: now), now: now, recap: RecapFacts(slot: slot, minutes: 95, place: stale))
        #expect(reminders.first?.body == "Last week: 1 h 35 m locked in.")
        // Alone on the leaderboard: no place worth saying.
        let alone = SquadPlace(squadName: "Library Goblins", place: 1, of: 1, week: slot.week)
        #expect(ReminderPlanner.place(alone, in: slot.week) == nil)
    }

    @Test func nothingToRecap() throws {
        let now = at(12)
        let slot = try #require(ReminderPlanner.recapSlot(after: now, quietHours: .default, calendar: sydney))
        #expect(plan(written(at: now), now: now, recap: RecapFacts(slot: slot, minutes: 0)).isEmpty)
    }

    @Test func switchedOff() throws {
        let now = at(12)
        let slot = try #require(ReminderPlanner.recapSlot(after: now, quietHours: .default, calendar: sydney))
        var settings = ReminderSettings.default
        settings.recapEnabled = false
        #expect(plan(written(at: now), now: now, settings: settings, recap: RecapFacts(slot: slot, minutes: 380)).isEmpty)
    }
}

@Suite struct DailyLimitTests {
    @Test func twoDeliveredAlreadyIsEnough() {
        let now = at(12)
        let log = ReminderLog(entries: [
            .init(kind: "other", at: at(8).timeIntervalSince1970),
            .init(kind: "other", at: at(10).timeIntervalSince1970),
        ])
        let data = written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)])
        #expect(plan(data, now: now, log: log).isEmpty)
        // Yesterday's don't count today.
        let yesterday = ReminderLog(entries: [
            .init(kind: "other", at: at(8, day: 14).timeIntervalSince1970),
            .init(kind: "other", at: at(10, day: 14).timeIntervalSince1970),
        ])
        #expect(plan(data, now: now, log: yesterday).count == 1)
    }

    @Test func whatsStillToComeIsReplacedNotCounted() {
        let now = at(12)
        let log = ReminderLog(entries: [
            .init(kind: ReminderKind.streak.rawValue, at: at(19).timeIntervalSince1970),
            .init(kind: "other", at: at(10).timeIntervalSince1970),
        ])
        let data = written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)])
        #expect(plan(data, now: now, log: log).map(\.fireDate) == [at(19)])
    }

    @Test func onAMondayTheStreakComesFirst() throws {
        let now = at(7, day: 18)
        let slot = try #require(ReminderPlanner.recapSlot(after: now, quietHours: .default, calendar: sydney))
        let data = written(at: now, squads: [squad("Library Goblins", streak: 6, counted: false)])
        let recap = RecapFacts(slot: slot, minutes: 380)
        // Both fit: recap at 09:00, streak at 19:00.
        let both = plan(data, now: now, recap: recap)
        #expect(both.map(\.kind) == [.recap, .streak])
        // One delivered already: room for one more, the streak.
        let log = ReminderLog(entries: [.init(kind: "other", at: at(6, day: 18).timeIntervalSince1970)])
        #expect(plan(data, now: now, log: log, recap: recap).map(\.kind) == [.streak])
    }
}

@Suite struct ReminderLogTests {
    @Test func planningReplacesWhatsToCome() {
        let now = at(12)
        var log = ReminderLog(entries: [
            .init(kind: "streak", at: at(19, day: 1).timeIntervalSince1970),
            .init(kind: "streak", at: at(19, day: 14).timeIntervalSince1970),
            .init(kind: "streak", at: at(19).timeIntervalSince1970),
        ])
        let next = PlannedReminder(kind: .streak, fireDate: at(19, day: 16), body: "", identifier: "lk.reminder.streak.2027-01-16")
        log.replaceUpcoming(with: [next], at: now)
        // A fortnight ago is forgotten, yesterday's stays, today's 19:00 is replaced.
        #expect(log.entries.map(\.date) == [at(19, day: 14), at(19, day: 16)])
        #expect(log.delivered(onDayOf: at(19, day: 14), before: now, calendar: sydney) == 1)
        #expect(log.delivered(onDayOf: at(19, day: 16), before: now, calendar: sydney) == 0)
    }

    @Test func otherNotificationsCount() {
        var log = ReminderLog()
        log.record(kind: "boost", at: at(9))
        #expect(log.delivered(onDayOf: at(23), before: at(12), calendar: sydney) == 1)
        #expect(log.delivered(onDayOf: at(23), before: at(8), calendar: sydney) == 0)
    }

    @Test func savedInDefaults() {
        withScratchDefaults { defaults in
            #expect(ReminderLog.load(from: defaults) == ReminderLog())
            let log = ReminderLog(entries: [.init(kind: "recap", at: 1_800_000_000)])
            log.save(to: defaults)
            #expect(ReminderLog.load(from: defaults) == log)
        }
    }
}

@Suite struct ReminderSettingsTests {
    @Test func theDefaultIsBothOnAtSevenInTheEvening() {
        let settings = ReminderSettings.default
        #expect(settings.streakEnabled)
        #expect(settings.recapEnabled)
        #expect(settings.streakTime == 1_140)
    }

    @Test func timesWrapRoundTheClock() {
        #expect(ReminderSettings(streakTime: -60).streakTime == 1_380)
        var settings = ReminderSettings.default
        settings.streakTime = 1_500
        #expect(settings.streakTime == 60)
    }

    @Test func decodingIsLenient() throws {
        let empty = try JSONDecoder().decode(ReminderSettings.self, from: Data("{}".utf8))
        #expect(empty == .default)
        let partial = try JSONDecoder().decode(ReminderSettings.self, from: Data(#"{"streakEnabled":false,"streakTime":"late"}"#.utf8))
        #expect(partial == ReminderSettings(streakEnabled: false, streakTime: 1_140, recapEnabled: true))
    }

    @Test func savedInDefaults() {
        withScratchDefaults { defaults in
            #expect(ReminderSettings.load(from: defaults) == .default)
            let settings = ReminderSettings(streakEnabled: true, streakTime: 18 * 60 + 30, recapEnabled: false)
            settings.save(to: defaults)
            #expect(ReminderSettings.load(from: defaults) == settings)
            defaults.set(Data("not json".utf8), forKey: ReminderSettings.defaultsKey)
            #expect(ReminderSettings.load(from: defaults) == .default)
        }
    }
}

@Suite struct ReminderWordsTests {
    @Test func ordinals() {
        let words = [1, 2, 3, 4, 10, 11, 12, 13, 21, 22, 23, 101, 111, 112].map(ReminderPlanner.ordinal)
        #expect(words == ["1st", "2nd", "3rd", "4th", "10th", "11th", "12th", "13th", "21st", "22nd", "23rd", "101st", "111th", "112th"])
    }

    @Test func possessives() {
        #expect(ReminderPlanner.possessive("Library Goblins") == "Library Goblins'")
        #expect(ReminderPlanner.possessive("Night Owl") == "Night Owl's")
        #expect(ReminderPlanner.possessive("BOSS") == "BOSS'")
    }

    @Test func identifiersCarryThePrefix() {
        let id = ReminderPlanner.identifier(.recap, on: at(9, day: 5, month: 3), calendar: sydney)
        #expect(id == "lk.reminder.recap.2027-03-05")
        #expect(id.hasPrefix(ReminderPlanner.identifierPrefix))
    }
}
