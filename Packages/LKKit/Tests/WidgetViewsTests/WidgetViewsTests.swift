import Foundation
import Model
import SwiftUI
import Testing
import WidgetKit
@testable import WidgetViews

/// What the widgets show, worked out from the App Group's `WidgetData` (docs/milestones/M6.md).
@Suite struct PetWidgetContentTests {
    static let first = WidgetSamples.squad
    static let second = WidgetSamples.newSquad

    static func data(squads: [WidgetData.Squad]) -> WidgetData {
        WidgetData(avatar: "b3.c7.e2.h4", todayMinutes: 45, soloStreak: 3, squads: squads, updatedAt: 1_800_000_000)
    }

    @Test func showsThePickedSquad() {
        let content = PetWidgetContent(data: Self.data(squads: [Self.first, Self.second]), squadID: Self.second.id)
        #expect(content == .squad(Self.second))
    }

    @Test func showsTheFirstSquadWithNothingPicked() {
        let content = PetWidgetContent(data: Self.data(squads: [Self.first, Self.second]), squadID: nil)
        #expect(content == .squad(Self.first))
    }

    /// A squad you've left since picking it.
    @Test func fallsBackToTheFirstSquadWhenThePickedOneIsGone() {
        let content = PetWidgetContent(data: Self.data(squads: [Self.first]), squadID: "sqGone00001")
        #expect(content == .squad(Self.first))
    }

    @Test func withNoSquadsItsYou() {
        let content = PetWidgetContent(data: Self.data(squads: []), squadID: Self.first.id)
        #expect(content == .solo(avatar: AvatarCode("b3.c7.e2.h4"), streak: 3, todayMinutes: 45))
        #expect(content.url == nil)
    }

    @Test func aSquadOpensOnHome() throws {
        let content = PetWidgetContent(data: Self.data(squads: [Self.first]), squadID: nil)
        let url = try #require(content.url)
        #expect(url.absoluteString == "lockin://squad/sqLibGob01")
    }
}

@Suite struct LockInWidgetStateTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func idleWithNoSession() {
        let data = WidgetData(todayMinutes: 45)
        #expect(LockInWidgetState(data: data, now: Self.now) == .idle(todayMinutes: 45))
    }

    @Test func runningCountsDownToTheEnd() {
        var data = WidgetData()
        data.session = WidgetData.Session(endsAt: Self.now.timeIntervalSince1970 + 600, squadName: "Night Owls")
        #expect(LockInWidgetState(data: data, now: Self.now) == .running(ends: Self.now.addingTimeInterval(600), squadName: "Night Owls"))
    }

    @Test func pausedShowsTheTimeLeft() {
        var data = WidgetData()
        data.session = WidgetData.Session(
            endsAt: Self.now.timeIntervalSince1970 + 600,
            pausedAt: Self.now.timeIntervalSince1970 - 300
        )
        #expect(LockInWidgetState(data: data, now: Self.now) == .paused(remaining: 900, squadName: nil))
    }

    /// The timer ran out before the app wrote that it's over: the button again.
    @Test func aSessionWhoseTimeRanOutIsIdle() {
        var data = WidgetData(todayMinutes: 20)
        data.session = WidgetData.Session(endsAt: Self.now.timeIntervalSince1970 - 1)
        #expect(LockInWidgetState(data: data, now: Self.now) == .idle(todayMinutes: 20))
    }
}

@Suite struct WidgetTimelineTests {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2027-01-15 08:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let midnight = Date(timeIntervalSince1970: 1_800_057_600)

    @Test func nowAndMidnightWithNoSession() {
        let dates = WidgetTimeline.entryDates(for: WidgetData(), from: Self.now, calendar: Self.utc)
        #expect(dates == [Self.now, Self.midnight])
    }

    @Test func aRunningSessionAddsItsEnd() {
        var data = WidgetData()
        let end = Self.now.addingTimeInterval(25 * 60)
        data.session = WidgetData.Session(endsAt: end.timeIntervalSince1970)
        let dates = WidgetTimeline.entryDates(for: data, from: Self.now, calendar: Self.utc)
        #expect(dates == [Self.now, end, Self.midnight])
    }

    @Test func aPausedOrFinishedSessionAddsNothing() {
        var data = WidgetData()
        data.session = WidgetData.Session(endsAt: Self.now.timeIntervalSince1970 + 600, pausedAt: Self.now.timeIntervalSince1970)
        #expect(WidgetTimeline.entryDates(for: data, from: Self.now, calendar: Self.utc) == [Self.now, Self.midnight])
        data.session = WidgetData.Session(endsAt: Self.now.timeIntervalSince1970 - 600)
        #expect(WidgetTimeline.entryDates(for: data, from: Self.now, calendar: Self.utc) == [Self.now, Self.midnight])
    }

    @Test func aSessionPastMidnightComesAfterIt() {
        var data = WidgetData()
        let end = Self.midnight.addingTimeInterval(600)
        data.session = WidgetData.Session(endsAt: end.timeIntervalSince1970)
        let late = Self.midnight.addingTimeInterval(-600)
        #expect(WidgetTimeline.entryDates(for: data, from: late, calendar: Self.utc) == [late, Self.midnight, end])
    }
}

@Suite struct WidgetWordsTests {
    @Test func streaks() {
        #expect(WidgetWords.streak(0) == "No streak yet")
        #expect(WidgetWords.streak(-3) == "No streak yet")
        #expect(WidgetWords.streak(1) == "1 day")
        #expect(WidgetWords.streak(12) == "12 days")
    }

    @Test func pets() {
        #expect(WidgetWords.pet(PetCode("sprout.2")) == "Sprout · teen")
        #expect(WidgetWords.pet(PetCode("ember.0")) == "Egg")
        #expect(WidgetWords.mood(3) == "Happy")
        #expect(WidgetWords.mood(-1) == "Sad")
    }

    @Test func clocks() {
        #expect(WidgetWords.clock(0) == "0:00")
        #expect(WidgetWords.clock(59.9) == "0:59")
        #expect(WidgetWords.clock(17 * 60) == "17:00")
        #expect(WidgetWords.clock(3_900) == "1:05:00")
        #expect(WidgetWords.clock(-5) == "0:00")
        #expect(WidgetWords.clock(.infinity) == "0:00")
    }
}

/// Every family draws, for squads and solo, in full colour and in one colour.
@MainActor
@Suite struct WidgetRenderingTests {
    static let sizes: [(WidgetFamily, CGSize)] = [
        (.systemSmall, CGSize(width: 170, height: 170)),
        (.systemMedium, CGSize(width: 364, height: 170)),
        (.accessoryCircular, CGSize(width: 76, height: 76)),
        (.accessoryRectangular, CGSize(width: 172, height: 76)),
    ]

    @Test func everyFamilyRenders() throws {
        let contents: [PetWidgetContent] = [
            .squad(WidgetSamples.squad),
            .squad(WidgetSamples.newSquad),
            .solo(avatar: WidgetSamples.avatar, streak: 3, todayMinutes: 45),
        ]
        for content in contents {
            for (family, size) in Self.sizes {
                for isFullColor in [true, false] {
                    let view = SquadPetWidgetView(content: content, family: family, isFullColor: isFullColor)
                        .frame(width: size.width, height: size.height)
                    let renderer = ImageRenderer(content: view)
                    let image = try #require(renderer.cgImage)
                    #expect(image.width > 0 && image.height > 0)
                }
            }
        }
    }

    @Test func lockInRendersEveryState() throws {
        let now = Date()
        for data in [WidgetSamples.solo(now: now), WidgetSamples.running(now: now), WidgetSamples.paused(now: now)] {
            let view = LockInWidgetView(data: data, now: now)
                .frame(width: 170, height: 170)
            let image = try #require(ImageRenderer(content: view).cgImage)
            #expect(image.width > 0)
        }
    }
}
