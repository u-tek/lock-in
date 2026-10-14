import Foundation
import Model
@testable import SessionEngine

/// A clock the tests move by hand. Only ever touched from the main actor.
final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(minutes: Double) {
        now = now.addingTimeInterval(minutes * 60)
    }

    func advance(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// 2027-01-15 08:00 UTC: a fixed start for the timing tests.
let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

/// Sydney: day boundaries in a real time zone, with daylight saving.
let sydney: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
    return calendar
}()

/// A local time in `calendar`.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar = sydney) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@MainActor
func makeEngine(clock: TestClock, store: SessionStore = .inMemory()) -> SessionEngine {
    SessionEngine(store: store, liveActivities: nil, now: { clock.now })
}

extension SessionEngine.Phase {
    var record: SessionRecord? {
        if case .finished(let record) = self {
            return record
        }
        return nil
    }
}

/// Collects event names from an `Analytics` sink.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(name)
    }
}

/// A record that ended at `end`, focused for `minutes`.
func record(endingAt end: Date, minutes: Int, completed: Bool = true) -> SessionRecord {
    SessionRecord(
        id: UUID().uuidString,
        startedAt: end.addingTimeInterval(-TimeInterval(minutes * 60)),
        endedAt: end,
        plannedMinutes: minutes,
        focusedSeconds: minutes * 60,
        completed: completed,
        coinsEarned: minutes
    )
}
