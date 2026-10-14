import Foundation

/// The squad pet's numbers and the arithmetic on them (docs/milestones/M5.md, "Rules").
///
/// The server is authoritative: it adds the XP, picks the species and works out the stage, the
/// progress and the mood, and the Live Activity shows what it sends. The app uses these to show a
/// squad's pet between updates and to explain the rules. Both sides test their copy against
/// `fixtures/pet/rules.json` at the repository root, so change the file, this, and the server
/// together.
public enum PetRules {
    /// Every species the server picks from when a squad is made. The `Creature` module draws each
    /// one; a species missing here (from a newer server) draws as the first.
    public static let species: [String] = ["puff", "sprout", "ember", "pebble"]

    /// The XP each stage starts at, by stage: 0 egg, 1 baby, 2 teen, 3 adult, then the prestige
    /// forms. XP is focused minutes. The egg and the baby both start at 0: hatching is the first
    /// finished group session, not an amount of XP.
    public static let stageXp: [Int] = [0, 0, 600, 3_000, 10_000, 25_000]

    /// A finished session counts towards the squad's streak from this many focused minutes.
    public static let streakMinMinutes = 20

    /// The share of the squad (rounded up, at least one member) that has to finish a counting
    /// session for the day to count.
    public static let streakShare = 0.5

    /// The pet stays sad this long after someone slips or leaves a squad session early.
    public static let sadMinutes = 30

    /// Coins per whole focused minute, solo or squad.
    public static let coinsPerMinute = 1

    /// The last stage there is. Stages past the table's end don't exist yet.
    public static var lastStage: Int {
        stageXp.count - 1
    }

    /// The stage a squad's pet is at: 0, the egg, until it hatches; then the highest stage whose
    /// XP it has, never below 1.
    public static func stage(xp: Int, hatched: Bool) -> Int {
        guard hatched else { return 0 }
        let reached = stageXp.indices.last(where: { xp >= stageXp[$0] }) ?? 0
        return max(1, reached)
    }

    /// How far the pet is from `stage` to the next, 0–1: 0 for an egg, 1 at the last stage.
    ///
    /// A stage the table doesn't have counts as the last; XP below the stage's start (which the
    /// server never sends) as no progress.
    public static func progress(xp: Int, stage: Int) -> Double {
        guard stage >= 1 else { return 0 }
        guard stage < lastStage else { return 1 }
        let start = Double(stageXp[stage])
        let end = Double(stageXp[stage + 1])
        guard end > start else { return 1 }
        return min(max((Double(xp) - start) / (end - start), 0), 1)
    }

    /// Every mood's name, saddest first: the index is the mood's number (`Pet.md`).
    public static let moodNames: [String] = PetMood.allCases.map(\.name)

    /// A mood's name ("sad", "hungry", "content", "happy"); numbers out of range are held to 0–3.
    public static func moodName(_ mood: Int) -> String {
        PetMood(level: mood).name
    }
}

/// The squad pet's mood today (docs/milestones/M5.md), as carried in `Pet.md`.
public enum PetMood: Int, CaseIterable, Sendable {
    /// Someone slipped or left a squad session early in the last `PetRules.sadMinutes`.
    case sad = 0
    /// Nobody in the squad has finished a session today.
    case hungry = 1
    /// Someone has, but today doesn't count for the streak yet.
    case content = 2
    /// Today counts.
    case happy = 3

    /// A mood from its number, held to 0–3: a newer server's mood still shows as one of these.
    public init(level: Int) {
        self = PetMood(rawValue: min(max(level, PetMood.sad.rawValue), PetMood.happy.rawValue)) ?? .sad
    }

    /// Lowercase, for sentences and VoiceOver: "Squad pet, teen sprout, happy". English only until
    /// the app has a string catalogue.
    public var name: String {
        switch self {
        case .sad: "sad"
        case .hungry: "hungry"
        case .content: "content"
        case .happy: "happy"
        }
    }
}
