import Foundation
import Model
import Testing
@testable import LiveActivity

private typealias WireMember = LockinAttributes.ContentState.Member
private typealias WirePet = LockinAttributes.ContentState.Pet

/// Ten minutes into the fixtures' session.
private let now = LiveActivitySamples.fixtureDate
private let t = now.timeIntervalSince1970

/// A member ten minutes into a session that ends at `end`.
private func wire(_ id: String, _ state: MemberState, end: Double = t + 900, pausedAt: Double? = nil, name: String? = nil) -> WireMember {
    WireMember(i: id, n: name ?? id, a: "b0.c0.e0.h0", s: state.rawValue, b: t - 600, e: end, q: pausedAt)
}

private func squad(_ members: [WireMember], me: String = "me", pet: WirePet? = nil) -> LiveActivityPresentation {
    LiveActivityPresentation(
        attributes: LockinAttributes(sid: "r7Kq2xP9aL", me: me, sq: "Library Goblins"),
        state: LockinAttributes.ContentState(v: 1, m: members, p: pet)
    )
}

private func solo(_ member: WireMember) -> LiveActivityPresentation {
    LiveActivityPresentation(
        attributes: LockinAttributes(sid: "s0LoRun123", me: member.i),
        state: LockinAttributes.ContentState(v: 1, m: [member])
    )
}

private func range(_ member: WireMember) -> ClosedRange<Date> {
    Date(timeIntervalSince1970: member.b)...Date(timeIntervalSince1970: member.e)
}

@Suite struct LayoutTests {
    @Test func squadOfSixPutsMeFirstAndShowsEveryone() throws {
        let presentation = LiveActivitySamples.squadOfSix(now: now).presentation
        #expect(!presentation.isSolo)
        #expect(presentation.members.map(\.name) == ["Ava", "Noor", "Kai", "Mateo", "Sakura", "Jules"])
        let me = try #require(presentation.primary)
        #expect(me.isMe)
        #expect(me.name == "Ava")
        #expect(presentation.members.filter(\.isMe).count == 1)

        #expect(presentation.lockScreenMembers.count == 6)
        // The expanded row is everyone but me (I'm beside the camera), four at most.
        #expect(presentation.expandedMembers.map(\.name) == ["Noor", "Kai", "Mateo", "Sakura"])
        #expect(presentation.expandedOverflow == 1)

        #expect(presentation.headline == "Library Goblins")
        #expect(presentation.statusLine == "1 of 6 locked in")
        #expect(presentation.pet?.title == "Sprout · teen")
    }

    @Test func membersAreCappedForEachPresentation() {
        // A server bug sending eight: the views still draw six and four.
        let members = (0..<8).map { wire("m\($0)", .focusing) }
        let presentation = squad(members, me: "m3")
        #expect(presentation.members.count == 8)
        #expect(presentation.lockScreenMembers.count == LiveActivityPresentation.lockScreenLimit)
        #expect(presentation.lockScreenMembers.first?.id == "m3")
        #expect(presentation.expandedMembers.count == LiveActivityPresentation.expandedLimit)
        #expect(presentation.expandedMembers.map(\.id) == ["m0", "m1", "m2", "m4"])
        #expect(presentation.expandedOverflow == 3)
        #expect(!presentation.expandedMembers.contains { $0.isMe })
    }

    @Test func smallSquadsHaveNoOverflow() {
        let presentation = squad([wire("me", .focusing), wire("ava", .onBreak)])
        #expect(presentation.expandedMembers.map(\.id) == ["ava"])
        #expect(presentation.expandedOverflow == 0)
    }

    @Test func withoutMeTheHostLeads() throws {
        // A join the server hasn't pushed yet: I'm not in the state.
        let presentation = squad([wire("host", .focusing), wire("ava", .focusing), wire("kai", .onBreak)], me: "late")
        let primary = try #require(presentation.primary)
        #expect(primary.id == "host")
        #expect(!presentation.members.contains { $0.isMe })
        #expect(presentation.expandedMembers.map(\.id) == ["ava", "kai"])
        // The "+N" leaves out whoever the compact island already shows.
        #expect(presentation.compactTrailing == .squadmates(1))
    }

    @Test func emptyStatesDrawNothingAndDontTrap() {
        let presentation = squad([])
        #expect(presentation.primary == nil)
        #expect(presentation.members.isEmpty)
        #expect(presentation.lockScreenMembers.isEmpty)
        #expect(presentation.expandedMembers.isEmpty)
        #expect(presentation.compactTrailing == .empty)
        #expect(presentation.compactTrailing.staticText == nil)
        #expect(presentation.sessionProgress == .hidden)
        #expect(presentation.statusLine == "0 of 0 locked in")

        let soloEmpty = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "s0LoRun123", me: "me"),
            state: LockinAttributes.ContentState(v: 1, m: [])
        )
        #expect(soloEmpty.headline == "Session")
    }

    @Test func repeatedMemberIdsAppearOnce() {
        let presentation = squad([wire("me", .focusing), wire("ava", .focusing), wire("ava", .done), wire("me", .left)])
        #expect(presentation.members.map(\.id) == ["me", "ava"])
        #expect(presentation.members.map(\.state) == [.focusing, .focusing])
    }

    @Test func soloShowsOnlyMe() throws {
        let presentation = LiveActivitySamples.solo(now: now).presentation
        #expect(presentation.isSolo)
        #expect(presentation.headline == "Locked in")
        #expect(presentation.statusLine == "Solo session")
        #expect(presentation.expandedMembers.isEmpty)
        #expect(presentation.pet == nil)
        let me = try #require(presentation.primary)
        #expect(me.isMe)
    }

    @Test(arguments: [
        (MemberState.focusing, "Locked in"),
        (MemberState.onBreak, "On a break"),
        (MemberState.paused, "Paused"),
        (MemberState.done, "Session done"),
        (MemberState.left, "Ended early"),
        (MemberState.slipped, "Slipped"),
    ])
    func soloHeadlines(state: MemberState, headline: String) {
        #expect(LiveActivitySamples.solo(now: now, me: state).presentation.headline == headline)
    }

    @Test func squadNamesAreFitted() {
        let long = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "r7Kq2xP9aL", me: "me", sq: "  The Extremely Long Squad Name Club  "),
            state: LockinAttributes.ContentState(v: 1, m: [wire("me", .focusing)])
        )
        // Cut at 20 scalars, which can land mid-word.
        #expect(long.headline == "The Extremely Long S")
        #expect(long.headline.unicodeScalars.count <= LiveActivityLimits.maxSquadNameLength)

        let blank = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "r7Kq2xP9aL", me: "me", sq: "   "),
            state: LockinAttributes.ContentState(v: 1, m: [wire("me", .focusing)])
        )
        #expect(!blank.isSolo)
        #expect(blank.headline == "Your squad")
    }
}

@Suite struct CompactTrailingTests {
    @Test func countsSquadmatesWhoAreFocusing() {
        let presentation = squad([
            wire("me", .focusing),
            wire("ava", .focusing),
            wire("noor", .focusing),
            wire("kai", .focusing),
            wire("jules", .onBreak),
            wire("mateo", .paused, pausedAt: t),
        ])
        #expect(presentation.othersFocusing == 3)
        #expect(presentation.focusingCount == 4)
        #expect(presentation.compactTrailing == .squadmates(3))
        #expect(presentation.compactTrailing.staticText == "+3")
        #expect(presentation.compactTrailingAccessibilityLabel == "3 squadmates locked in")
    }

    @Test func myOwnStateDoesntCount() {
        let presentation = squad([wire("me", .paused, pausedAt: t), wire("ava", .focusing), wire("kai", .done)])
        #expect(presentation.compactTrailing == .squadmates(1))
        #expect(presentation.compactTrailingAccessibilityLabel == "1 squadmate locked in")
    }

    @Test func withNobodyElseFocusingItShowsMyTime() throws {
        // squad-6: only Ava (me) is focusing.
        let presentation = LiveActivitySamples.squadOfSix(now: now).presentation
        #expect(presentation.othersFocusing == 0)
        let me = try #require(presentation.primary)
        #expect(presentation.compactTrailing == .countdown(me.countdown, tone: me.tone))
        #expect(presentation.compactTrailing.staticText == nil)
        #expect(presentation.compactTrailingAccessibilityLabel == "Ava, you, focusing")
    }

    @Test func soloShowsMyTimeEvenWithOthersInTheState() {
        // Solo attributes never show "+N", whatever the state holds.
        let presentation = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "s0LoRun123", me: "me"),
            state: LockinAttributes.ContentState(v: 1, m: [wire("me", .focusing), wire("ava", .focusing)])
        )
        guard case .countdown(.running, _) = presentation.compactTrailing else {
            Issue.record("Expected my running timer, got \(presentation.compactTrailing)")
            return
        }
    }

    @Test func soloFinishedShowsAWord() {
        let presentation = solo(wire("me", .done, end: t))
        #expect(presentation.compactTrailing.staticText == "Done")
    }
}

@Suite struct CountdownTests {
    @Test func focusingAndBreaksRunOnTheDevice() {
        let ava = wire("ava", .focusing)
        let noor = wire("noor", .onBreak, end: t + 300)
        let presentation = squad([ava, noor], me: "ava")
        #expect(presentation.members[0].countdown == .running(range(ava)))
        #expect(presentation.members[1].countdown == .running(range(noor)))
        #expect(presentation.members[0].countdown.staticText == nil)
        #expect(presentation.members[0].countdown.frozenRemaining == nil)
    }

    @Test func pausedTimersAreFrozen() throws {
        // Kai in squad-6: paused at the fixture date with 13 minutes to go.
        let presentation = LiveActivitySamples.squadOfSix(now: now).presentation
        let kai = try #require(presentation.members.first { $0.name == "Kai" })
        let expected = Date(timeIntervalSince1970: t - 720)...Date(timeIntervalSince1970: t + 780)
        #expect(kai.countdown == .paused(expected, pausedAt: now))
        #expect(kai.countdown.pausedAt == now)
        #expect(kai.countdown.frozenRemaining == 780)
        #expect(kai.accessibilityLabel == "Kai, paused, 13 minutes left")
    }

    @Test func pauseTimesAreHeldInsideTheTimer() {
        let early = squad([wire("me", .paused, end: t + 900, pausedAt: t - 5_000)])
        #expect(early.primary?.countdown.pausedAt == Date(timeIntervalSince1970: t - 600))
        #expect(early.primary?.countdown.frozenRemaining == 1_500)

        let late = squad([wire("me", .paused, end: t + 900, pausedAt: t + 5_000)])
        #expect(late.primary?.countdown.pausedAt == Date(timeIntervalSince1970: t + 900))
        #expect(late.primary?.countdown.frozenRemaining == 0)
        #expect(late.primary?.accessibilityLabel == "me, you, paused, under a minute left")
    }

    @Test func aPauseWithoutATimeIsAWord() {
        let presentation = squad([wire("me", .paused)])
        #expect(presentation.primary?.countdown == .text("Paused"))

        let broken = squad([wire("me", .paused, pausedAt: .nan)])
        #expect(broken.primary?.countdown == .text("Paused"))
    }

    @Test(arguments: [
        (MemberState.done, "Done"),
        (MemberState.left, "Left"),
        (MemberState.slipped, "Slipped"),
    ])
    func finishedMembersShowAWordNotATimer(state: MemberState, word: String) throws {
        let presentation = squad([wire("me", .focusing), wire("ava", state)])
        let ava = try #require(presentation.members.last)
        #expect(ava.countdown == .text(word))
        #expect(ava.countdown.staticText == word)
        #expect(ava.countdown.range == nil)
        #expect(ava.countdown.reservedWidth(fontSize: 15) == nil)
    }

    @Test(arguments: [9, 42, -1])
    func unknownStatesFallBackToFocusing(raw: Int) throws {
        // A state from a newer server: drawn as focusing, with a running timer, and counted.
        let future = WireMember(i: "ava", n: "Ava", a: "b0", s: raw, b: t - 600, e: t + 900)
        let presentation = squad([wire("me", .done, end: t), future])
        let ava = try #require(presentation.members.last)
        #expect(ava.state == .focusing)
        #expect(ava.tone.rawValue == MemberState.focusing.rawValue)
        #expect(ava.countdown == .running(range(future)))
        #expect(presentation.compactTrailing == .squadmates(1))
    }

    @Test func reservedWidthsMakeRoomForHours() {
        let short = squad([wire("me", .focusing)]).primary?.countdown
        #expect(short?.needsHours == false)
        #expect(short?.reservedWidth(fontSize: 15) == 45)

        let ninety = squad([wire("me", .focusing, end: t - 600 + 5_400)]).primary?.countdown
        #expect(ninety?.needsHours == true)
        #expect(ninety?.reservedWidth(fontSize: 15) == 60)

        // A long session paused with under an hour left needs no hours digit.
        let pausedLate = squad([wire("me", .paused, end: t + 1_800, pausedAt: t)]).primary?.countdown
        #expect(pausedLate?.needsHours == false)
    }

    @Test func backwardsTimesNeverTrap() {
        // An end before the start collapses to an empty timer rather than an inverted range.
        let backwards = WireMember(i: "me", n: "Me", a: "b0", s: 0, b: t, e: t - 100)
        let presentation = solo(backwards)
        #expect(presentation.primary?.countdown.range?.isEmpty == false)
        #expect(presentation.sessionProgress == .fixed(1))
    }
}

@Suite struct MemberTests {
    @Test func everyStateHasItsOwnLook() {
        for state in MemberState.allCases {
            #expect(LiveActivityPresentation.tone(for: state).rawValue == state.rawValue)
        }
    }

    @Test func accessibilityLabelsNameTheStateAndWhoIsMe() {
        let presentation = LiveActivitySamples.squadOfSix(now: now).presentation
        let labels = presentation.members.map(\.accessibilityLabel)
        #expect(labels == [
            "Ava, you, focusing",
            "Noor, on a break",
            "Kai, paused, 13 minutes left",
            "Mateo, done",
            "Sakura, left",
            "Jules, slipped",
        ])
    }

    @Test func namesAreFittedAndNeverBlank() {
        let presentation = squad([
            wire("me", .focusing, name: "   "),
            wire("ava", .focusing, name: "Bartholomew-Jones"),
        ])
        #expect(presentation.members[0].name == "Someone")
        #expect(presentation.members[1].name == "Bartholomew-")
        #expect(presentation.members[1].name.unicodeScalars.count == LiveActivityLimits.maxNameLength)
    }

    @Test func avatarIsCarriedForTheLockling() {
        let ava = WireMember(i: "ava", n: "Ava", a: "b3.c7.e2.h4", s: 0, b: t - 600, e: t + 900)
        let presentation = solo(ava)
        #expect(presentation.primary?.avatar == AvatarCode(body: 3, colour: 7, eyes: 2, hat: 4))
    }

    @Test func aGarbledAvatarStillDraws() {
        // From a newer app version, or broken: parts read as the defaults, never a failure.
        let ava = WireMember(i: "ava", n: "Ava", a: "b99.x7.%%", s: 0, b: t - 600, e: t + 900)
        #expect(solo(ava).primary?.avatar == AvatarCode(body: 99))
    }
}

/// The buttons under a solo session's timer (Pause or Resume, and End).
@Suite struct SessionControlTests {
    @Test(arguments: [
        (MemberState.focusing, LiveActivityPresentation.SessionControls.pauseAndEnd),
        (MemberState.onBreak, LiveActivityPresentation.SessionControls.pauseAndEnd),
        (MemberState.paused, LiveActivityPresentation.SessionControls.resumeAndEnd),
        (MemberState.done, LiveActivityPresentation.SessionControls.hidden),
        (MemberState.left, LiveActivityPresentation.SessionControls.hidden),
        (MemberState.slipped, LiveActivityPresentation.SessionControls.hidden),
    ])
    func soloSessionsCanBePausedResumedAndEnded(state: MemberState, controls: LiveActivityPresentation.SessionControls) {
        #expect(LiveActivitySamples.solo(now: now, me: state).presentation.sessionControls == controls)
    }

    @Test func squadsHaveNoSessionButtonsYet() {
        // Squad sessions and their buttons (Cheer) arrive in M2.
        #expect(LiveActivitySamples.squadOfSix(now: now).presentation.sessionControls == .hidden)
        #expect(LiveActivitySamples.squadOfFour(now: now).presentation.sessionControls == .hidden)
    }

    @Test func onlyYourOwnSessionHasButtons() {
        // A solo state that somehow lacks me: whoever leads isn't mine to pause.
        let presentation = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "s0LoRun123", me: "me"),
            state: LockinAttributes.ContentState(v: 1, m: [wire("someone", .focusing)])
        )
        #expect(presentation.sessionControls == .hidden)
        let empty = LiveActivityPresentation(
            attributes: LockinAttributes(sid: "s0LoRun123", me: "me"),
            state: LockinAttributes.ContentState(v: 1, m: [])
        )
        #expect(empty.sessionControls == .hidden)
    }
}

@Suite struct WordingTests {
    @Test(arguments: [
        (0.0, "under a minute left"),
        (59.0, "under a minute left"),
        (60.0, "1 minute left"),
        (119.0, "1 minute left"),
        (780.0, "13 minutes left"),
        (3_600.0, "1 hour left"),
        (3_660.0, "1 hour 1 minute left"),
        (3_900.0, "1 hour 5 minutes left"),
        (7_260.0, "2 hours 1 minute left"),
        (14_400.0, "4 hours left"),
        (-30.0, "under a minute left"),
        (Double.nan, "under a minute left"),
        (Double.infinity, "under a minute left"),
    ])
    func remainingPhrases(seconds: Double, phrase: String) {
        #expect(LiveActivityPresentation.remainingPhrase(seconds) == phrase)
    }

    @Test func absurdTimesDontTrap() {
        // A broken end time far in the future still produces words rather than overflowing Int.
        #expect(LiveActivityPresentation.remainingPhrase(1e300).hasSuffix(" left"))
    }
}

@Suite struct ProgressTests {
    @Test func runningSessionsFillOnTheDevice() {
        let me = wire("me", .focusing)
        #expect(solo(me).sessionProgress == .live(range(me)))
    }

    @Test func pausedSessionsShowWhereTheyStopped() {
        // Paused 10 minutes into 25.
        let presentation = solo(wire("me", .paused, end: t + 900, pausedAt: t))
        #expect(presentation.sessionProgress == .fixed(600.0 / 1_500.0))
    }

    @Test(arguments: [
        (MemberState.done, LiveActivityPresentation.SessionProgress.fixed(1)),
        (MemberState.left, LiveActivityPresentation.SessionProgress.hidden),
        (MemberState.slipped, LiveActivityPresentation.SessionProgress.hidden),
    ])
    func finishedSessions(state: MemberState, progress: LiveActivityPresentation.SessionProgress) {
        #expect(solo(wire("me", state)).sessionProgress == progress)
    }
}

@Suite struct PetTests {
    @Test(arguments: [
        (1.7, 1.0),
        (-0.2, 0.0),
        (Double.nan, 0.0),
        (0.64, 0.64),
    ])
    func progressIsHeldToOne(raw: Double, progress: Double) throws {
        let presentation = squad([wire("me", .focusing)], pet: WirePet(k: "fox.2", md: 2, x: raw))
        let pet = try #require(presentation.pet)
        #expect(pet.progress == progress)
    }

    @Test(arguments: [(9, 3), (-1, 0), (2, 2)])
    func moodIsHeldToTheRamp(raw: Int, mood: Int) throws {
        let presentation = squad([wire("me", .focusing)], pet: WirePet(k: "fox.2", md: raw, x: 0.5))
        let pet = try #require(presentation.pet)
        #expect(pet.mood == mood)
    }

    @Test(arguments: [
        ("sprout.2", "Sprout · teen"),
        ("pebble.1", "Pebble · baby"),
        ("ember.4", "Ember · prestige"),
        ("puff.5", "Puff · prestige 2"),
        // A species this version can't draw (it draws a puff) keeps its own name.
        ("fox.2", "Fox · teen"),
        ("owl.3", "Owl · adult"),
        ("dragonling.12", "Dragonling · prestige 9"),
        // The species is a surprise until the egg hatches.
        ("ember.0", "Egg"),
        ("%%%", "Egg"),
    ])
    func titles(code: String, title: String) throws {
        let presentation = squad([wire("me", .focusing)], pet: WirePet(k: code, md: 1, x: 0.5))
        let pet = try #require(presentation.pet)
        #expect(pet.title == title)
    }

    @Test func accessibilityLabelNeverSaysAHundredTooEarly() throws {
        let nearly = squad([wire("me", .focusing)], pet: WirePet(k: "fox.2", md: 2, x: 0.999))
        let pet = try #require(nearly.pet)
        #expect(pet.accessibilityLabel == "Squad pet, fox, teen, content, 99 percent of the way to the next stage")
    }

    /// The pet's face shows its mood, so VoiceOver says it too.
    @Test(arguments: [(0, "sad"), (1, "hungry"), (2, "content"), (3, "happy"), (9, "happy")])
    func accessibilityLabelSaysTheMood(mood: Int, name: String) throws {
        let presentation = squad([wire("me", .focusing)], pet: WirePet(k: "sprout.3", md: mood, x: 0.25))
        let pet = try #require(presentation.pet)
        #expect(pet.accessibilityLabel == "Squad pet, sprout, adult, \(name), 25 percent of the way to the next stage")
    }

    @Test func anEggKeepsItsSpeciesToItself() throws {
        let presentation = squad([wire("me", .focusing)], pet: WirePet(k: "ember.0", md: 3, x: 0))
        let pet = try #require(presentation.pet)
        #expect(pet.title == "Egg")
        #expect(pet.accessibilityLabel == "Squad pet, egg, happy")
        #expect(!pet.accessibilityLabel.contains("ember"))
        // It still draws in its species' colours.
        #expect(pet.code == PetCode(species: "ember", stage: 0))
    }

    @Test func soloHasNoPet() {
        #expect(LiveActivitySamples.solo(now: now).presentation.pet == nil)
    }
}
