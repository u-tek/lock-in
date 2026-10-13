import Foundation

/// The squad pet's species and stage, as carried in `Pet.k`: `<species>.<stage>`, e.g. "fox.2".
///
/// Parsing never fails, for the same reason as `AvatarCode`: a code from a newer server may name a
/// species this app version can't draw yet. A garbled species reads as `defaultSpecies` and a
/// garbled stage as 0, the egg. The species catalogue itself arrives with the pet (M5).
public struct PetCode: Hashable, Sendable, CustomStringConvertible {
    /// Lowercase ASCII letters, digits, "-" and "_".
    public var species: String
    /// 0 egg, 1 baby, 2 teen, 3 adult, 4 and up prestige forms.
    public var stage: Int

    public init(species: String = PetCode.defaultSpecies, stage: Int = 0) {
        self.species = species
        self.stage = max(0, stage)
    }

    /// Reads a code leniently. Anything after the stage is ignored.
    public init(_ code: String) {
        let parts = code.split(separator: ".", omittingEmptySubsequences: false)
        let species = parts.first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let stage = parts.count > 1 ? Self.number(parts[1].trimmingCharacters(in: .whitespaces)) : nil
        self.init(
            species: Self.isValidSpecies(species) ? species : Self.defaultSpecies,
            stage: stage ?? 0
        )
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

    public var code: String {
        "\(species).\(stage)"
    }

    public var description: String {
        code
    }

    /// Drawn when a code's species can't be read.
    public static let defaultSpecies = "fox"

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
}
