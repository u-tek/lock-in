import Foundation
import Testing
@testable import Model

/// Inputs no well-behaved server sends. Parsing them must never trap.
let unreadableCodes: [String] = [
    "",
    ".",
    "....",
    " ",
    "b",
    "b.",
    ".b3",
    "b3..c7",
    "🦊",
    "b🦊",
    "b3🦊",
    "b٣",
    "b３",
    "b+3",
    "b-3",
    "b 3",
    "b3c7e2h4",
    "c7\ne2",
    "\u{0}",
    "b\u{0}3",
    "fox.",
    "fox..2",
    ".fox.2",
    "fox.2.3.4",
    "e\u{301}\u{301}\u{301}.2",
    String(repeating: "9", count: 400),
    "b" + String(repeating: "9", count: 400),
    String(repeating: "b9.", count: 10_000),
    String(repeating: "🔒.", count: 1_000),
]

@Suite struct AvatarCodeTests {
    @Test func readsTheCanonicalForm() {
        let avatar = AvatarCode("b3.c7.e2.h4")
        #expect(avatar == AvatarCode(body: 3, colour: 7, eyes: 2, hat: 4))
        #expect(avatar.code == "b3.c7.e2.h4")
        #expect(avatar.description == "b3.c7.e2.h4")
    }

    @Test func partsCanComeInAnyOrder() {
        #expect(AvatarCode("h4.e2.c7.b3") == AvatarCode("b3.c7.e2.h4"))
        #expect(AvatarCode("c7.b3").code == "b3.c7.e0.h0")
    }

    @Test func unknownPartsAreSkipped() {
        // Parts a newer app version might add.
        #expect(AvatarCode("b1.z9.c2.w33.e5.h6").code == "b1.c2.e5.h6")
        #expect(AvatarCode("b3.c7.e2.h4.g12").code == "b3.c7.e2.h4")
    }

    @Test func missingAndGarbledPartsReadAsTheDefault() {
        #expect(AvatarCode("") == .default)
        #expect(AvatarCode("b5").code == "b5.c0.e0.h0")
        #expect(AvatarCode("bx.c-1.e.h99999999999999999999999") == .default)
        #expect(AvatarCode("b+3.c 7.e٣.h３") == .default)
        #expect(AvatarCode.default.code == "b0.c0.e0.h0")
    }

    @Test func theFirstWellFormedPartWins() {
        #expect(AvatarCode("b2.b5").body == 2)
        #expect(AvatarCode("bx.b5").body == 5)
    }

    @Test func toleratesSpacesAndLeadingZeros() {
        #expect(AvatarCode(" b3 . c07 ").code == "b3.c7.e0.h0")
    }

    @Test func lettersAreLowercase() {
        #expect(AvatarCode("B3.C7") == .default)
    }

    @Test func negativeIndicesAreClamped() {
        #expect(AvatarCode(body: -1, colour: -2, eyes: -3, hat: -4) == .default)
    }

    @Test(arguments: unreadableCodes)
    func garbageNeverTrapsAndSettlesOnACanonicalCode(input: String) {
        let avatar = AvatarCode(input)
        #expect(AvatarCode(avatar.code) == avatar)
        #expect(avatar.code.hasPrefix("b"))
        #expect(avatar.code.split(separator: ".").count == 4)
    }
}

@Suite struct PetCodeTests {
    @Test func readsSpeciesAndStage() {
        let pet = PetCode("fox.2")
        #expect(pet.species == "fox")
        #expect(pet.stage == 2)
        #expect(pet.growth == .teen)
        #expect(pet.prestigeLevel == 0)
        #expect(pet.code == "fox.2")
        #expect(pet.description == "fox.2")
    }

    @Test func stagesBeyondAdultArePrestigeForms() {
        let pet = PetCode("dragonling.12")
        #expect(pet.species == "dragonling")
        #expect(pet.growth == .prestige)
        #expect(pet.prestigeLevel == 9)
        #expect(PetCode("fox.4").prestigeLevel == 1)
        #expect(PetCode("fox.3").growth == .adult)
        #expect(PetCode("fox.3").prestigeLevel == 0)
    }

    @Test(arguments: [
        (-5, PetCode.Growth.egg),
        (0, PetCode.Growth.egg),
        (1, PetCode.Growth.baby),
        (2, PetCode.Growth.teen),
        (3, PetCode.Growth.adult),
        (4, PetCode.Growth.prestige),
        (Int.max, PetCode.Growth.prestige),
    ])
    func growthFromStage(stage: Int, expected: PetCode.Growth) {
        #expect(PetCode.Growth(stage: stage) == expected)
    }

    @Test func missingOrGarbledStageIsAnEgg() {
        #expect(PetCode("fox") == PetCode(species: "fox", stage: 0))
        #expect(PetCode("fox.x").stage == 0)
        #expect(PetCode("fox.-1").stage == 0)
        #expect(PetCode("fox.+1").stage == 0)
        #expect(PetCode("fox.99999999999999999999999").stage == 0)
        #expect(PetCode("fox.").growth == .egg)
    }

    @Test func garbledSpeciesFallsBackToTheDefault() {
        #expect(PetCode("").code == "\(PetCode.defaultSpecies).0")
        #expect(PetCode(".3").code == "\(PetCode.defaultSpecies).3")
        #expect(PetCode("🦊.2").code == "\(PetCode.defaultSpecies).2")
        #expect(PetCode("a b.1").species == PetCode.defaultSpecies)
        #expect(PetCode(String(repeating: "x", count: 33) + ".1").species == PetCode.defaultSpecies)
        #expect(PetCode.default == PetCode(species: PetCode.defaultSpecies, stage: 0))
    }

    @Test func normalisesCaseSpacesAndExtraParts() {
        #expect(PetCode("FOX.1").code == "fox.1")
        #expect(PetCode(" fox . 2 ").code == "fox.2")
        #expect(PetCode("fox.2.extra").code == "fox.2")
        #expect(PetCode("sea-otter_2.1").species == "sea-otter_2")
    }

    @Test func negativeStagesAreClamped() {
        #expect(PetCode(species: "fox", stage: -3).stage == 0)
    }

    @Test(arguments: unreadableCodes)
    func garbageNeverTrapsAndSettlesOnACanonicalCode(input: String) {
        let pet = PetCode(input)
        #expect(PetCode(pet.code) == pet)
        #expect(!pet.species.isEmpty)
        #expect(pet.stage >= 0)
    }
}

@Suite struct SessionPresetTests {
    @Test func standardPresets() {
        #expect(SessionPreset.standard.map(\.minutes) == [25, 50, 90])
        #expect(SessionPreset.twentyFive.duration == 1_500)
        #expect(SessionPreset.ninety.duration == 5_400)
        let anyNeedPlus = SessionPreset.standard.contains { $0.requiresPlus }
        #expect(!anyNeedPlus)
    }

    @Test func customLengthsAreClampedToTheSessionCap() {
        #expect(SessionPreset.customRange == 1...240)
        #expect(SessionPreset.custom(minutes: 45).minutes == 45)
        #expect(SessionPreset.custom(minutes: 0).minutes == 1)
        #expect(SessionPreset.custom(minutes: -30).minutes == 1)
        #expect(SessionPreset.custom(minutes: 500).minutes == 240)
        #expect(SessionPreset.custom(minutes: Int.max).duration == LiveActivityLimits.maxSessionSeconds)
        #expect(SessionPreset.custom(minutes: 45).requiresPlus)
    }

    @Test func savedLengthsReadBackAsTheMatchingPreset() {
        #expect(SessionPreset(minutes: 25) == .twentyFive)
        #expect(SessionPreset(minutes: 50) == .fifty)
        #expect(SessionPreset(minutes: 90) == .ninety)
        #expect(SessionPreset(minutes: 45) == .custom(minutes: 45))
        #expect(SessionPreset(minutes: 1_000) == .custom(minutes: 240))
        #expect(SessionPreset(minutes: 0) == .custom(minutes: 1))
    }
}

@Suite struct LiveActivityLimitsTests {
    @Test func limitsMatchTheSpec() {
        #expect(LiveActivityLimits.payloadBudgetBytes == 3_584)
        #expect(LiveActivityLimits.systemLimitBytes == 4_096)
        #expect(LiveActivityLimits.payloadBudgetBytes < LiveActivityLimits.systemLimitBytes)
        #expect(LiveActivityLimits.maxMembers == 6)
        #expect(LiveActivityLimits.maxNameLength == 12)
        #expect(LiveActivityLimits.maxSquadNameLength == 20)
        #expect(LiveActivityLimits.maxSessionSeconds == 14_400)
        #expect(LiveActivityLimits.staleGraceSeconds == 300)
        #expect(LiveActivityLimits.dismissalAfterEndSeconds == 1_800)
    }

    @Test func fittedNamesKeepWholeCharactersWithinTheLimit() {
        #expect(LiveActivityLimits.fittedName("Ava") == "Ava")
        #expect(LiveActivityLimits.fittedName("  Ava \n") == "Ava")
        // "Bartholomew " is 12; the trailing space is trimmed.
        #expect(LiveActivityLimits.fittedName("Bartholomew the Great") == "Bartholomew")
        #expect(LiveActivityLimits.fittedName(String(repeating: "🦊", count: 20)) == String(repeating: "🦊", count: 12))
        #expect(LiveActivityLimits.fittedSquadName(String(repeating: "🔒", count: 25)) == String(repeating: "🔒", count: 20))
    }

    @Test func emojiSequencesAreNeverSplit() {
        // A family is one character of seven scalars: one fits in 12, a second doesn't.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        #expect(family.unicodeScalars.count == 7)
        #expect(LiveActivityLimits.fittedName(family + family) == family)
    }

    @Test func combiningMarksCantInflateAName() {
        let zalgo = "e" + String(repeating: "\u{301}", count: 50) + "va"
        let fitted = LiveActivityLimits.fittedName(zalgo)
        #expect(fitted.unicodeScalars.count <= LiveActivityLimits.maxNameLength)
        #expect(fitted.utf8.count <= LiveActivityLimits.maxNameLength * 4)
    }
}
