import Foundation

/// The squad pet's species and stage, as carried in `Pet.k`: `<species>.<stage>`, e.g. "sprout.2",
/// and while the squad is boosted (M7, Squad Boost) the accessory it wears: `"sprout.2.a3"`.
///
/// Parsing never fails, for the same reason as `AvatarCode`: a code from a newer server may name a
/// species this app version can't draw yet. A garbled species reads as `defaultSpecies` and a
/// garbled stage as 0, the egg. A well-formed species is kept even when it isn't one of
/// `PetRules.species`: the `Creature` module draws those as the default. A garbled accessory reads
/// as none, and one this version doesn't know (`.a7` and up) is kept but not drawn.
public struct PetCode: Hashable, Sendable, CustomStringConvertible {
    /// Lowercase ASCII letters, digits, "-" and "_".
    public var species: String
    /// 0 egg, 1 baby, 2 teen, 3 adult, 4 and up prestige forms.
    public var stage: Int
    /// The accessory it wears, `accessoryRange` (the `n` of `pet.<n>` in the shop's catalogue), or
    /// nil for none. `wornAccessory` is the one this version can draw.
    public var accessory: Int?

    public init(species: String = PetCode.defaultSpecies, stage: Int = 0, accessory: Int? = nil) {
        self.species = species
        self.stage = max(0, stage)
        self.accessory = accessory.flatMap { Self.accessoryRange.contains($0) ? $0 : nil }
    }

    /// Reads a code leniently. After the stage, only an accessory (`a<n>`) is read; anything else
    /// is ignored.
    public init(_ code: String) {
        let parts = code.split(separator: ".", omittingEmptySubsequences: false)
        let species = parts.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let stage = parts.count > 1 ? Self.number(parts[1].trimmingCharacters(in: .whitespaces)) : nil
        let accessory = parts.count > 2 ? Self.accessoryNumber(parts[2].trimmingCharacters(in: .whitespaces)) : nil
        self.init(
            species: Self.isValidSpecies(species) ? species : Self.defaultSpecies,
            stage: stage ?? 0,
            accessory: accessory
        )
    }

    /// The accessories the server accepts in a pet code: `.a1` to `.a99`.
    public static let accessoryRange = 1...99

    /// The accessory, when this version knows how to draw it.
    public var wornAccessory: PetAccessory? {
        accessory.flatMap(PetAccessory.init(rawValue:))
    }

    public enum Growth: Int, CaseIterable, Sendable {
        case egg = 0
        case baby = 1
        case teen = 2
        case adult = 3
        /// Cosmetic forms after adult (stages 4 and up).
        case prestige = 4

        public init(stage: Int) {
            self = Growth(rawValue: min(max(stage, 0), Growth.prestige.rawValue)) ?? .egg
        }
    }

    public var growth: Growth {
        Growth(stage: stage)
    }

    /// 0 until adult; 1 for the first prestige form (stage 4), and so on.
    public var prestigeLevel: Int {
        max(0, stage - Growth.adult.rawValue)
    }

    /// The stage in words: "egg", "baby", "teen", "adult", then "prestige", "prestige 2" and on.
    /// English only until the app has a string catalogue.
    public var stageName: String {
        switch growth {
        case .egg: "egg"
        case .baby: "baby"
        case .teen: "teen"
        case .adult: "adult"
        case .prestige: prestigeLevel > 1 ? "prestige \(prestigeLevel)" : "prestige"
        }
    }

    /// "sprout.2", or "sprout.2.a3" wearing an accessory.
    public var code: String {
        guard let accessory else { return "\(species).\(stage)" }
        return "\(species).\(stage).a\(accessory)"
    }

    public var description: String {
        code
    }

    /// Drawn when a code's species can't be read: the first of `PetRules.species`.
    public static let defaultSpecies = "puff"

    public static let `default` = PetCode()

    private static func isValidSpecies(_ species: String) -> Bool {
        !species.isEmpty && species.count <= 32 && species.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    private static func number(_ digits: String) -> Int? {
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// "a3" → 3. Nil for anything else, and outside `accessoryRange`.
    private static func accessoryNumber(_ part: String) -> Int? {
        let lowered = part.lowercased()
        guard lowered.hasPrefix("a"), let value = number(String(lowered.dropFirst())) else { return nil }
        return accessoryRange.contains(value) ? value : nil
    }
}
