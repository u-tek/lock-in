import Foundation
import Testing
@testable import SessionEngine

// The stats on their own, in Sydney's time zone: local midnights, and a daylight saving change
// (clocks went forward at 02:00 on 4 October 2026).

@Suite struct FocusStatsTests {
    private func stats(_ history: [SessionRecord], now: Date) -> FocusStats {
        FocusStats.compute(history: history, coins: 7, completedSessions: 2, now: now, calendar: sydney)
    }

    @Test func emptyHistory() {
        let result = stats([], now: date(2027, 3, 10))
        #expect(result == FocusStats(todayMinutes: 0, streakDays: 0, coins: 7, completedSessions: 2))
    }

    @Test func todayCountsSessionsThatEndedToday() {
        let history = [
            record(endingAt: date(2027, 3, 9, 23, 59), minutes: 25),
            // Started yesterday, finished after midnight: today's.
            record(endingAt: date(2027, 3, 10, 0, 15), minutes: 25),
            record(endingAt: date(2027, 3, 10, 9, 0), minutes: 50),
            record(endingAt: date(2027, 3, 11, 9, 0), minutes: 90),
        ]
        #expect(stats(history, now: date(2027, 3, 10, 10, 0)).todayMinutes == 75)
        #expect(stats(history, now: date(2027, 3, 10, 0, 0)).todayMinutes == 75)
        #expect(stats(history, now: date(2027, 3, 9, 23, 59).addingTimeInterval(30)).todayMinutes == 25)
    }

    @Test func partialMinutesAddUpBeforeRounding() {
        let half = SessionRecord(
            id: "a", startedAt: date(2027, 3, 10, 8), endedAt: date(2027, 3, 10, 9),
            plannedMinutes: 25, focusedSeconds: 90, completed: false, coinsEarned: 1
        )
        // 90 + 90 seconds is 3 minutes, not 1 + 1.
        #expect(stats([half, half], now: date(2027, 3, 10, 12)).todayMinutes == 3)
    }

    @Test func streakCountsConsecutiveDaysWithTwentyMinutes() {
        let history = [
            record(endingAt: date(2027, 3, 5), minutes: 60),
            // Not enough on the 6th: the streak starts after it.
            record(endingAt: date(2027, 3, 6), minutes: 10),
            record(endingAt: date(2027, 3, 7), minutes: 25),
            record(endingAt: date(2027, 3, 8), minutes: 20),
            record(endingAt: date(2027, 3, 9), minutes: 30),
        ]
        #expect(stats(history, now: date(2027, 3, 9, 18)).streakDays == 3)
    }

    @Test func todayNotDoneYetKeepsYesterdaysStreak() {
        let history = [
            record(endingAt: date(2027, 3, 8), minutes: 25),
            record(endingAt: date(2027, 3, 9), minutes: 25),
            record(endingAt: date(2027, 3, 10, 8), minutes: 5),
        ]
        #expect(stats(history, now: date(2027, 3, 10, 9)).streakDays == 2)
        // Finishing today extends it.
        let more = history + [record(endingAt: date(2027, 3, 10, 10), minutes: 15)]
        #expect(stats(more, now: date(2027, 3, 10, 11)).streakDays == 3)
    }

    @Test func aMissedDayBreaksTheStreak() {
        let history = [
            record(endingAt: date(2027, 3, 7), minutes: 25),
            record(endingAt: date(2027, 3, 8), minutes: 25),
            // Nothing on the 9th.
            record(endingAt: date(2027, 3, 10), minutes: 25),
        ]
        #expect(stats(history, now: date(2027, 3, 10, 20)).streakDays == 1)
        #expect(stats(history, now: date(2027, 3, 11, 20)).streakDays == 1)
        #expect(stats(history, now: date(2027, 3, 12, 8)).streakDays == 0)
    }

    @Test func shortSessionsOnOneDayAddUpToTheMinimum() {
        let history = [
            record(endingAt: date(2027, 3, 10, 9), minutes: 10, completed: false),
            record(endingAt: date(2027, 3, 10, 15), minutes: 10, completed: false),
        ]
        #expect(stats(history, now: date(2027, 3, 10, 16)).streakDays == 1)
    }

    @Test func streakRunsThroughADaylightSavingChange() {
        let history = (1...6).map { day in record(endingAt: date(2026, 10, day, 21), minutes: 25) }
        #expect(stats(history, now: date(2026, 10, 6, 22)).streakDays == 6)
        // The 4th was 23 hours long.
        #expect(stats(Array(history.prefix(3)), now: date(2026, 10, 4, 1, 30)).streakDays == 3)
        #expect(stats(Array(history.prefix(5)), now: date(2026, 10, 5, 22)).streakDays == 5)
    }

    @Test func historyOrderDoesNotMatter() {
        let history = [
            record(endingAt: date(2027, 3, 10), minutes: 25),
            record(endingAt: date(2027, 3, 8), minutes: 25),
            record(endingAt: date(2027, 3, 9), minutes: 25),
        ]
        #expect(stats(history, now: date(2027, 3, 10, 22)).streakDays == 3)
    }

    @Test func coinsPerMinuteAndTheFinishingBonus() {
        #expect(SessionRecord.coins(focusedSeconds: 25 * 60, completed: true) == 30)
        #expect(SessionRecord.coins(focusedSeconds: 25 * 60 - 1, completed: false) == 24)
        #expect(SessionRecord.coins(focusedSeconds: 59, completed: false) == 0)
        #expect(SessionRecord.coins(focusedSeconds: -10, completed: false) == 0)
    }
}
