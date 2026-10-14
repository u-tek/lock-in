import Foundation
import Testing
@testable import Notifications

/// Sydney: a real time zone, with daylight saving (clocks go forward at 02:00 on the first Sunday
/// of October).
private let sydney: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
    return calendar
}()

/// A local time in Sydney.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 15, month: Int = 1) -> Date {
    sydney.date(from: DateComponents(year: 2027, month: month, day: day, hour: hour, minute: minute))!
}

/// Defaults of their own for one test, emptied afterwards.
private func withScratchDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let name = "NotificationsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    try body(defaults)
}

@Suite struct QuietHoursTests {
    @Test func theDefaultIsTenAtNightToSevenInTheMorning() {
        let quiet = QuietHours.default
        #expect(quiet.isEnabled)
        #expect(quiet.start == 1_320)
        #expect(quiet.end == 420)
        #expect(quiet.crossesMidnight)
        #expect(quiet.window?.start == 1_320)
        #expect(quiet.window?.end == 420)
    }

    @Test func aWindowAcrossMidnight() {
        let quiet = QuietHours.default
        #expect(!quiet.contains(date: at(21, 59), calendar: sydney))
        #expect(quiet.contains(date: at(22, 0), calendar: sydney))
        #expect(quiet.contains(date: at(23, 59), calendar: sydney))
        #expect(quiet.contains(date: at(0, 0), calendar: sydney))
        #expect(quiet.contains(date: at(3, 30), calendar: sydney))
        #expect(quiet.contains(date: at(6, 59), calendar: sydney))
        #expect(!quiet.contains(date: at(7, 0), calendar: sydney))
        #expect(!quiet.contains(date: at(12, 0), calendar: sydney))
    }

    @Test func aWindowWithinTheDay() {
        let siesta = QuietHours(start: 13 * 60, end: 14 * 60 + 30)
        #expect(!siesta.crossesMidnight)
        #expect(!siesta.contains(date: at(12, 59), calendar: sydney))
        #expect(siesta.contains(date: at(13, 0), calendar: sydney))
        #expect(siesta.contains(date: at(14, 29), calendar: sydney))
        #expect(!siesta.contains(date: at(14, 30), calendar: sydney))
        #expect(!siesta.contains(date: at(23, 0), calendar: sydney))
    }

    @Test func offMeansNever() {
        var quiet = QuietHours.default
        quiet.isEnabled = false
        #expect(quiet.window?.start == nil)
        #expect(!quiet.contains(date: at(23, 0), calendar: sydney))
        #expect(!quiet.contains(date: at(3, 0), calendar: sydney))
    }

    @Test func fromAndToAtTheSameMinuteIsNoWindow() {
        let empty = QuietHours(start: 600, end: 600)
        #expect(empty.window?.start == nil)
        #expect(!empty.contains(date: at(10, 0), calendar: sydney))
        #expect(!empty.contains(date: at(22, 0), calendar: sydney))
    }

    @Test func minutesWrapRoundTheClock() {
        #expect(QuietHours(start: -60, end: 1_440) == QuietHours(start: 1_380, end: 0))
        #expect(QuietHours(start: 2_900, end: 7 * 60).start == 20)
        var quiet = QuietHours.default
        quiet.start = 1_500
        quiet.end = -1
        #expect(quiet.start == 60)
        #expect(quiet.end == 1_439)
    }

    @Test func itTimesTheLocalClock() {
        // 23:00 in Sydney is 12:00 UTC (summer, UTC+11): quiet there, not on a UTC clock.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let lateInSydney = at(23, 0)
        #expect(QuietHours.default.contains(date: lateInSydney, calendar: sydney))
        #expect(!QuietHours.default.contains(date: lateInSydney, calendar: utc))
    }

    @Test func pickerDatesRoundTrip() {
        for minutes in [0, 1, 59, 60, 420, 721, 1_320, 1_439] {
            let date = QuietHours.date(minutes: minutes, on: at(12), calendar: sydney)
            #expect(QuietHours.minutes(of: date, calendar: sydney) == minutes)
            #expect(sydney.isDate(date, inSameDayAs: at(12)))
        }
    }

    @Test func pickerDatesSurviveTheClocksChanging() {
        // 3 October 2027: Sydney's clocks jump from 02:00 to 03:00.
        let day = at(12, day: 3, month: 10)
        let late = QuietHours.date(minutes: 22 * 60, on: day, calendar: sydney)
        #expect(QuietHours.minutes(of: late, calendar: sydney) == 22 * 60)
        let skipped = QuietHours.date(minutes: 2 * 60 + 30, on: day, calendar: sydney)
        #expect(sydney.isDate(skipped, inSameDayAs: day))
    }

    @Test func codableRoundTrip() throws {
        let quiet = QuietHours(isEnabled: false, start: 23 * 60 + 30, end: 6 * 60 + 15)
        let data = try JSONEncoder().encode(quiet)
        #expect(try JSONDecoder().decode(QuietHours.self, from: data) == quiet)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["isEnabled"] as? Bool == false)
        #expect(object["start"] as? Int == 1_410)
        #expect(object["end"] as? Int == 375)
    }

    @Test func decodingIsLenient() throws {
        let empty = try JSONDecoder().decode(QuietHours.self, from: Data("{}".utf8))
        #expect(empty == .default)
        let partial = try JSONDecoder().decode(QuietHours.self, from: Data(#"{"isEnabled":false,"start":"late"}"#.utf8))
        #expect(partial == QuietHours(isEnabled: false, start: 1_320, end: 420))
    }

    @Test func savedInDefaults() {
        withScratchDefaults { defaults in
            #expect(QuietHours.load(from: defaults) == .default)
            let quiet = QuietHours(isEnabled: true, start: 21 * 60, end: 8 * 60)
            quiet.save(to: defaults)
            #expect(QuietHours.load(from: defaults) == quiet)
            defaults.set(Data("not json".utf8), forKey: QuietHours.defaultsKey)
            #expect(QuietHours.load(from: defaults) == .default)
        }
    }
}

@Suite struct JoinWithoutOpeningTests {
    @Test func offUntilSwitchedOn() {
        withScratchDefaults { defaults in
            #expect(!JoinWithoutOpening.isEnabled(defaults: defaults))
            JoinWithoutOpening.setEnabled(true, defaults: defaults)
            #expect(JoinWithoutOpening.isEnabled(defaults: defaults))
            JoinWithoutOpening.setEnabled(false, defaults: defaults)
            #expect(!JoinWithoutOpening.isEnabled(defaults: defaults))
        }
    }

    @Test func theLatestTokenIsKept() {
        withScratchDefaults { defaults in
            #expect(JoinWithoutOpening.savedToken(defaults: defaults) == nil)
            JoinWithoutOpening.save(token: "80a1b2", defaults: defaults)
            JoinWithoutOpening.save(token: "c3d4e5", defaults: defaults)
            #expect(JoinWithoutOpening.savedToken(defaults: defaults) == "c3d4e5")
            JoinWithoutOpening.save(token: "", defaults: defaults)
            #expect(JoinWithoutOpening.savedToken(defaults: defaults) == nil)
        }
    }

    @Test func theLastAttemptIsKept() {
        withScratchDefaults { defaults in
            #expect(JoinWithoutOpening.lastAttempt(defaults: defaults) == nil)
            let attempt = JoinWithoutOpening.Attempt(outcome: .pushedToStart, at: 1_800_000_000, seconds: 2.4)
            JoinWithoutOpening.record(attempt, defaults: defaults)
            #expect(JoinWithoutOpening.lastAttempt(defaults: defaults) == attempt)
        }
    }
}
