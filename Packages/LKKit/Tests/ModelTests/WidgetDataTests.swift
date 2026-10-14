import Foundation
import Testing
@testable import Model

/// The file the app writes for the widgets (docs/milestones/M6.md, "Widget data").
@Suite struct WidgetDataTests {
    /// 2027-01-15 08:00 UTC.
    static let written = Date(timeIntervalSince1970: 1_800_000_000)

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func squad(_ id: String = "sqLibGob01", streak: Int = 4, countedToday: Bool = true) -> WidgetData.Squad {
        WidgetData.Squad(
            id: id,
            name: "Library Goblins",
            pet: "sprout.2",
            mood: 3,
            progress: 0.4,
            streak: streak,
            countedToday: countedToday,
            lockedIn: 2
        )
    }

    static func sample(todayMinutes: Int = 45, squads: [WidgetData.Squad] = [squad()]) -> WidgetData {
        WidgetData(
            avatar: "b3.c7.e2.h4",
            todayMinutes: todayMinutes,
            soloStreak: 3,
            squads: squads,
            session: WidgetData.Session(endsAt: 1_800_000_900, pausedAt: nil, squadName: "Library Goblins"),
            updatedAt: written.timeIntervalSince1970
        )
    }

    // MARK: - JSON

    @Test func roundTripsThroughJSON() throws {
        let data = Self.sample()
        let decoded = try WidgetData(json: data.encoded())
        #expect(decoded == data)
    }

    /// The keys are the property names in M6.md, and a nil is left out rather than written as null.
    @Test func keysAreTheContractsNames() throws {
        let json = try Self.sample().encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(Set(object.keys) == ["avatar", "todayMinutes", "soloStreak", "squads", "session", "updatedAt"])
        let squads = try #require(object["squads"] as? [[String: Any]])
        #expect(Set(squads[0].keys) == ["id", "name", "pet", "mood", "progress", "streak", "countedToday", "lockedIn"])
        let session = try #require(object["session"] as? [String: Any])
        #expect(Set(session.keys) == ["endsAt", "squadName"])
        #expect(session["endsAt"] as? Double == 1_800_000_900)
    }

    @Test func noSessionLeavesTheKeyOut() throws {
        var data = Self.sample()
        data.session = nil
        let object = try #require(try JSONSerialization.jsonObject(with: data.encoded()) as? [String: Any])
        #expect(object["session"] == nil)
    }

    /// A few hundred bytes, even with three squads of the longest names.
    @Test func staysSmall() throws {
        let long = String(repeating: "W", count: 20)
        let squads = (0..<3).map { index in
            WidgetData.Squad(
                id: "sq\(index)AAAAAAA",
                name: long,
                pet: "pebble.12",
                mood: 3,
                progress: 0.333333333333,
                streak: 999,
                countedToday: true,
                lockedIn: 6
            )
        }
        let data = WidgetData(
            avatar: "b99.c99.e99.h99",
            todayMinutes: 1_440,
            soloStreak: 9_999,
            squads: squads,
            session: WidgetData.Session(endsAt: 1_800_014_400.5, pausedAt: 1_800_000_000.25, squadName: long),
            updatedAt: 1_800_000_000.123
        )
        #expect(try data.encoded().count < 1_024)
    }

    @Test func keepsAtMostThreeSquads() {
        let squads = (0..<5).map { Self.squad("sq\($0)AAAAAAA") }
        #expect(WidgetData(squads: squads).squads.count == WidgetData.maxSquads)
        #expect(WidgetData(squads: squads).squads.map(\.id) == squads.prefix(3).map(\.id))
    }

    @Test func aNewerAppsExtraKeysAreIgnored() throws {
        let json = """
        {"avatar":"b1.c2.e3.h4","todayMinutes":5,"soloStreak":1,"squads":[],"updatedAt":1800000000,"coins":12}
        """
        let data = try WidgetData(json: Data(json.utf8))
        #expect(data.avatarCode == AvatarCode("b1.c2.e3.h4"))
        #expect(data.session == nil)
    }

    @Test func comparesContentWithoutTheTimestamp() {
        let data = Self.sample()
        var later = data
        later.updatedAt += 60
        #expect(data.hasSameContent(as: later))
        later.todayMinutes += 1
        #expect(!data.hasSameContent(as: later))
    }

    // MARK: - Squads and sessions

    @Test func squadValuesAreHeldToTheirRanges() {
        var squad = Self.squad()
        squad.mood = 9
        squad.progress = 3
        #expect(squad.petMood == .happy)
        #expect(squad.clampedProgress == 1)
        squad.mood = -2
        squad.progress = .nan
        #expect(squad.petMood == .sad)
        #expect(squad.clampedProgress == 0)
        #expect(squad.petCode == PetCode(species: "sprout", stage: 2))
    }

    @Test func aPausedSessionIsFrozen() {
        let session = WidgetData.Session(endsAt: 1_000, pausedAt: 400)
        #expect(session.isPaused)
        #expect(session.remaining(at: Date(timeIntervalSince1970: 500)) == 600)
        #expect(session.remaining(at: Date(timeIntervalSince1970: 5_000)) == 600)
        #expect(session.isOngoing(at: Date(timeIntervalSince1970: 5_000)))
    }

    @Test func aRunningSessionEndsWhenItsTimeRunsOut() {
        let session = WidgetData.Session(endsAt: 1_000)
        #expect(session.remaining(at: Date(timeIntervalSince1970: 400)) == 600)
        #expect(session.isOngoing(at: Date(timeIntervalSince1970: 999)))
        #expect(!session.isOngoing(at: Date(timeIntervalSince1970: 1_000)))
        #expect(session.remaining(at: Date(timeIntervalSince1970: 2_000)) == 0)
    }

    // MARK: - Days

    @Test func theSameDayChangesNothing() {
        let data = Self.sample()
        let evening = Self.written.addingTimeInterval(12 * 3_600)
        #expect(data.asSeen(at: evening, calendar: Self.utc) == data)
        // A clock set back doesn't either.
        #expect(data.asSeen(at: Self.written.addingTimeInterval(-3 * 86_400), calendar: Self.utc) == data)
    }

    @Test func theNextDayStartsAfresh() throws {
        let data = Self.sample()
        let tomorrow = Self.written.addingTimeInterval(86_400)
        let seen = data.asSeen(at: tomorrow, calendar: Self.utc)
        #expect(seen.todayMinutes == 0)
        // 45 minutes counted yesterday, so the streak lives on until tonight.
        #expect(seen.soloStreak == 3)
        let squad = try #require(seen.squads.first)
        #expect(squad.streak == 4)
        #expect(!squad.countedToday)
        #expect(squad.petMood == .hungry)
        // What isn't about the day stays.
        #expect(seen.avatar == data.avatar)
        #expect(seen.session == data.session)
        #expect(seen.updatedAt == data.updatedAt)
        #expect(squad.pet == "sprout.2")
        #expect(squad.lockedIn == 2)
    }

    @Test func aStreakThatDidntCountTheDayItWasWrittenBreaksTheNextDay() {
        let data = Self.sample(todayMinutes: 10, squads: [Self.squad(countedToday: false)])
        let seen = data.asSeen(at: Self.written.addingTimeInterval(86_400), calendar: Self.utc)
        #expect(seen.soloStreak == 0)
        #expect(seen.squads.first?.streak == 0)
    }

    @Test func twoDaysLaterEveryStreakHasBroken() {
        let data = Self.sample()
        let seen = data.asSeen(at: Self.written.addingTimeInterval(2 * 86_400), calendar: Self.utc)
        #expect(seen.soloStreak == 0)
        #expect(seen.squads.first?.streak == 0)
    }

    // MARK: - Store

    @Test func theStoreSavesAndLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDataTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetDataStore(url: directory.appendingPathComponent(WidgetDataStore.fileName))

        #expect(store.load() == nil)
        let data = Self.sample()
        #expect(store.save(data))
        #expect(store.load() == data)

        var changed = data
        changed.squads = []
        changed.session = nil
        #expect(store.save(changed))
        #expect(store.load() == changed)
    }

    @Test func anUnreadableFileLoadsAsNothing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetDataTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(WidgetDataStore.fileName)
        try Data("not json".utf8).write(to: url)
        #expect(WidgetDataStore(url: url).load() == nil)
    }
}
