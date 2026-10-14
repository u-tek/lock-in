import Foundation
import Testing
@testable import Model

/// `fixtures/pet/rules.json` at the repository root: the pet's numbers, which the server's tests
/// read too (docs/milestones/M5.md). If either side changes a number without the other, one of
/// them fails.
enum PetRulesFixture {
    /// The file's keys and values, read with a plain `JSONDecoder()`.
    struct File: Decodable, Equatable {
        let species: [String]
        let stageXp: [Int]
        let streakMinMinutes: Int
        let streakShare: Double
        let sadMinutes: Int
        let coinsPerMinute: Int
        let completionBonus: Int
    }

    /// Walks up from this source file to the directory holding `fixtures/pet`, as `Fixture` does
    /// for the Live Activity's.
    static func data() throws -> Data {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in url.pathComponents.indices {
            let candidate = url.appendingPathComponent("fixtures/pet/rules.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try Data(contentsOf: candidate)
            }
            url = url.deletingLastPathComponent()
        }
        throw Fixture.NotFound(description: "No fixtures/pet/rules.json above \(#filePath)")
    }

    static func file() throws -> File {
        try JSONDecoder().decode(File.self, from: data())
    }
}

@Suite struct PetRulesFixtureTests {
    @Test func theSwiftRulesMatchTheFixture() throws {
        let file = try PetRulesFixture.file()
        #expect(file.species == PetRules.species)
        #expect(file.stageXp == PetRules.stageXp)
        #expect(file.streakMinMinutes == PetRules.streakMinMinutes)
        #expect(file.streakShare == PetRules.streakShare)
        #expect(file.sadMinutes == PetRules.sadMinutes)
        #expect(file.coinsPerMinute == PetRules.coinsPerMinute)
        #expect(file.completionBonus == PetRules.completionBonus)
    }

    /// A rule added to the file needs a constant here too (and a decision about what the app does
    /// with it), so an unknown key fails rather than being skipped by the decoder.
    @Test func theFixtureHasNoRuleTheAppDoesntKnow() throws {
        let keys = try Fixture.keys(PetRulesFixture.data())
        #expect(keys == [
            "species", "stageXp", "streakMinMinutes", "streakShare", "sadMinutes", "coinsPerMinute", "completionBonus",
        ])
    }

    @Test func theTableIsWellFormed() {
        // The egg and the baby both start at 0; every stage after costs more than the last.
        #expect(PetRules.stageXp.count >= 5)
        #expect(PetRules.stageXp[0] == 0 && PetRules.stageXp[1] == 0)
        for stage in 2..<PetRules.stageXp.count {
            #expect(PetRules.stageXp[stage] > PetRules.stageXp[stage - 1], "stage \(stage)")
        }
        #expect(PetRules.lastStage == PetRules.stageXp.count - 1)
        #expect(Set(PetRules.species).count == PetRules.species.count)
        #expect(PetRules.streakShare > 0 && PetRules.streakShare <= 1)
    }

    /// A species the parser can't read draws as the first one there is.
    @Test func theDefaultSpeciesIsTheFirst() {
        #expect(PetCode.defaultSpecies == PetRules.species.first)
        for species in PetRules.species {
            #expect(PetCode("\(species).2").species == species)
        }
    }
}

@Suite struct PetStageTests {
    @Test func stage() {
        let table: [(xp: Int, hatched: Bool, stage: Int)] = [
            // Until it hatches it's an egg, however much XP it has.
            (0, false, 0),
            (5_000, false, 0),
            (99_999, false, 0),
            // Hatched: the highest stage it has the XP for, never below the baby.
            (0, true, 1),
            (-20, true, 1),
            (599, true, 1),
            (600, true, 2),
            (2_999, true, 2),
            (3_000, true, 3),
            (9_999, true, 3),
            (10_000, true, 4),
            (24_999, true, 4),
            (25_000, true, 5),
            // Nothing past the table's end yet.
            (1_000_000, true, 5),
            (Int.max, true, 5),
        ]
        for row in table {
            #expect(PetRules.stage(xp: row.xp, hatched: row.hatched) == row.stage, "\(row.xp) XP, hatched \(row.hatched)")
        }
    }

    @Test func progress() {
        let table: [(xp: Int, stage: Int, progress: Double)] = [
            // An egg's progress is 0.
            (1_000, 0, 0),
            // Baby: 0 to 600.
            (0, 1, 0),
            (150, 1, 0.25),
            (300, 1, 0.5),
            // Teen: 600 to 3,000.
            (600, 2, 0),
            (1_800, 2, 0.5),
            // Adult: 3,000 to 10,000; the first prestige form: 10,000 to 25,000.
            (6_500, 3, 0.5),
            (17_500, 4, 0.5),
            // The last stage is as far as it goes.
            (25_000, 5, 1),
            (999_999, 5, 1),
            // Held to 0–1, and stages the table doesn't have.
            (100, 3, 0),
            (50_000, 2, 1),
            (10, -1, 0),
            (10, 9, 1),
        ]
        for row in table {
            let progress = PetRules.progress(xp: row.xp, stage: row.stage)
            #expect(abs(progress - row.progress) < 1e-9, "\(row.xp) XP at stage \(row.stage): \(progress)")
        }
    }

    /// The two together, as the server uses them: every XP has a stage and a progress inside it,
    /// and each stage starts at 0 progress.
    @Test func stageAndProgressAgree() {
        for xp in stride(from: 0, through: 30_000, by: 50) {
            let stage = PetRules.stage(xp: xp, hatched: true)
            let progress = PetRules.progress(xp: xp, stage: stage)
            #expect(progress >= 0 && progress <= 1, "\(xp) XP")
            #expect(xp >= PetRules.stageXp[stage], "\(xp) XP")
        }
        for stage in 2...PetRules.lastStage {
            let xp = PetRules.stageXp[stage]
            #expect(PetRules.stage(xp: xp, hatched: true) == stage)
            #expect(PetRules.progress(xp: xp, stage: stage) == (stage == PetRules.lastStage ? 1 : 0))
        }
    }
}

@Suite struct PetMoodTests {
    @Test func namesRunFromSadToHappy() {
        #expect(PetRules.moodNames == ["sad", "hungry", "content", "happy"])
        #expect(PetMood.allCases.map(\.rawValue) == [0, 1, 2, 3])
    }

    @Test(arguments: [
        (-5, "sad"),
        (0, "sad"),
        (1, "hungry"),
        (2, "content"),
        (3, "happy"),
        (4, "happy"),
        (Int.min, "sad"),
        (Int.max, "happy"),
    ])
    func moodsAreHeldToTheRange(level: Int, name: String) {
        #expect(PetRules.moodName(level) == name)
        #expect(PetMood(level: level).name == name)
    }

    @Test(arguments: [
        ("puff.0", "egg"),
        ("puff.1", "baby"),
        ("puff.2", "teen"),
        ("puff.3", "adult"),
        ("puff.4", "prestige"),
        ("puff.5", "prestige 2"),
        ("puff.12", "prestige 9"),
    ])
    func stageNames(code: String, name: String) {
        #expect(PetCode(code).stageName == name)
    }
}
