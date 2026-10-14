import Foundation
import Testing
@testable import SessionEngine

/// The weekly recap's minutes (M6): sessions that ended inside the week, by when they ended.
@MainActor
@Suite struct WeekMinutesTests {
    @Test func sessionsThatEndedInTheWeek() {
        let store = SessionStore.inMemory()
        store.save(StoredSessions(history: [
            record(endingAt: date(2027, 1, 10, 23), minutes: 90),
            record(endingAt: date(2027, 1, 11, 0), minutes: 20),
            record(endingAt: date(2027, 1, 14, 12), minutes: 50),
            record(endingAt: date(2027, 1, 17, 23, 59), minutes: 25, completed: false),
            record(endingAt: date(2027, 1, 18, 0), minutes: 25),
        ]))
        let engine = makeEngine(clock: TestClock(date(2027, 1, 18, 9)), store: store)
        let week = DateInterval(start: date(2027, 1, 11, 0), end: date(2027, 1, 18, 0))
        #expect(engine.focusedMinutes(in: week) == 95)
        #expect(engine.focusedMinutes(in: DateInterval(start: date(2027, 1, 1, 0), end: date(2027, 1, 2, 0))) == 0)
    }
}
