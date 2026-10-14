import DeviceActivity
import Foundation
import Testing
@testable import DeepFocus

@Suite struct ScheduleTests {
    private let now = referenceDate

    @Test func deviceActivityRules() {
        #expect(DeepFocusSchedule.minimumInterval == 15 * 60)
        #expect(DeepFocusSchedule.maximumInterval < 24 * 3_600)
    }

    @Test func aLongSessionIsMonitoredFromNowToItsEnd() throws {
        let end = now.addingTimeInterval(minutes(25))
        let schedule = try #require(DeepFocusSchedule.ending(at: end, now: now))
        #expect(schedule == DeepFocusSchedule(start: now, end: end))
    }

    @Test func fractionsOfASecondNeverEndItEarly() throws {
        let start = now.addingTimeInterval(0.4)
        let end = now.addingTimeInterval(minutes(50) + 0.3)
        let schedule = try #require(DeepFocusSchedule.ending(at: end, now: start))
        #expect(schedule.start == now)
        #expect(schedule.end == now.addingTimeInterval(minutes(50) + 1))
        #expect(schedule.end >= end)
    }

    /// Under 16 minutes left, the interval reaches back into the past instead, so it's still long
    /// enough for DeviceActivity and still ends with the session.
    @Test(arguments: [30.0, 300, 600, 894, 900, 959])
    func shortRemaindersStartInThePast(secondsLeft: Double) throws {
        let end = now.addingTimeInterval(secondsLeft)
        let schedule = try #require(DeepFocusSchedule.ending(at: end, now: now))
        #expect(schedule.end == end)
        #expect(schedule.duration == DeepFocusSchedule.minimumInterval + DeepFocusSchedule.margin)
        #expect(schedule.start < now)
    }

    @Test func sixteenMinutesOrMoreStartsNow() throws {
        let schedule = try #require(DeepFocusSchedule.ending(at: now.addingTimeInterval(960), now: now))
        #expect(schedule.start == now)
        #expect(schedule.duration == 960)
    }

    @Test func everyIntervalIsLongEnoughAndCoversTheRest() throws {
        for secondsLeft in stride(from: 1.0, through: 4 * 3_600, by: 7.3) {
            let start = now.addingTimeInterval(0.6)
            let end = start.addingTimeInterval(secondsLeft)
            let schedule = try #require(DeepFocusSchedule.ending(at: end, now: start))
            #expect(schedule.duration >= DeepFocusSchedule.minimumInterval, "\(secondsLeft) s left")
            #expect(schedule.start <= start, "\(secondsLeft) s left")
            #expect(schedule.end >= end && schedule.end < end.addingTimeInterval(1), "\(secondsLeft) s left")
        }
    }

    @Test func nothingToMonitorOnceItsOver() {
        #expect(DeepFocusSchedule.ending(at: now, now: now) == nil)
        #expect(DeepFocusSchedule.ending(at: now.addingTimeInterval(-60), now: now) == nil)
    }

    @Test func aRunawayEndIsCapped() throws {
        let schedule = try #require(DeepFocusSchedule.ending(at: now.addingTimeInterval(30 * 3_600), now: now))
        #expect(schedule.end == now.addingTimeInterval(DeepFocusSchedule.maximumInterval))
        #expect(schedule.start == now)
    }

    @Test func theGraceTimerEndsFiveMinutesOn() throws {
        let schedule = try #require(DeepFocusSchedule.ending(at: now.addingTimeInterval(DeepFocusEngine.graceLength), now: now))
        #expect(schedule.end.timeIntervalSince(now) == 300)
        #expect(schedule.duration >= DeepFocusSchedule.minimumInterval)
    }

    /// Written as times of day, without dates: across midnight too.
    @Test func componentsAreTimesOfDay() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let lateNight = try #require(utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 23, minute: 55)))
        let end = lateNight.addingTimeInterval(minutes(25) + 30)
        let schedule = try #require(DeepFocusSchedule.ending(at: end, now: lateNight))
        let parts = schedule.components(in: utc)
        #expect(parts.start == DateComponents(hour: 23, minute: 55, second: 0))
        #expect(parts.end == DateComponents(hour: 0, minute: 20, second: 30))
        #expect(parts.start.year == nil && parts.start.day == nil && parts.start.calendar == nil)
    }

    @Test func aStretchedIntervalCanStartYesterday() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let justAfterMidnight = try #require(utc.date(from: DateComponents(year: 2027, month: 1, day: 16, hour: 0, minute: 2)))
        let schedule = try #require(DeepFocusSchedule.ending(at: justAfterMidnight.addingTimeInterval(minutes(5)), now: justAfterMidnight))
        let parts = schedule.components(in: utc)
        #expect(parts.start == DateComponents(hour: 23, minute: 51, second: 0))
        #expect(parts.end == DateComponents(hour: 0, minute: 7, second: 0))
    }

    @Test func activityNamesRoundTrip() {
        for activity in DeepFocusActivity.allCases {
            #expect(DeepFocusActivity(activity.name) == activity)
        }
        #expect(DeepFocusActivity.session.name.rawValue == "lockinSession")
        #expect(DeepFocusActivity.grace.name.rawValue == "lockinGrace")
    }
}
