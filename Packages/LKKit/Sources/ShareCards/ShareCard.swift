// ShareCards (M6, SPEC.md §1.7): the picture people post after a session. A 9:16 story and a 1:1
// square, drawn in SwiftUI (`ShareCardView`) and rendered at 1080 pixels wide with `ImageRenderer`
// (`ShareCardRenderer`), so the Locklings and the pet are the same shapes as everywhere else.
//
// Names: yours, and those of the squad that just finished together, nobody else's
// (docs/milestones/M6.md). Nothing here touches the network.

import Foundation
import Model

/// What goes on a share card.
public struct ShareCard: Hashable, Sendable {
    /// Someone you just locked in with.
    public struct Member: Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var avatar: AvatarCode

        public init(id: String, name: String, avatar: AvatarCode) {
            self.id = id
            self.name = name
            self.avatar = avatar
        }
    }

    /// Your Lockling.
    public var avatar: AvatarCode
    /// What to call you under your Lockling in a squad's lineup. Nil: "You".
    public var name: String?
    /// The squad that just finished together; nil for a solo session.
    public var squadName: String?
    /// The others in that session, in the room's order (you're not among them). Empty when solo.
    public var squadmates: [Member]
    /// Minutes locked in this session.
    public var minutes: Int
    /// Days in a row.
    public var streak: Int
    /// The squad's pet, if it has one to show.
    public var pet: PetCode?
    /// The pet's mood, 0–3 (`PetMood`).
    public var petMood: Int
    /// Your friend code, for "Lock in with me on Lockin".
    public var inviteCode: String?

    public init(
        avatar: AvatarCode,
        name: String? = nil,
        squadName: String? = nil,
        squadmates: [Member] = [],
        minutes: Int,
        streak: Int,
        pet: PetCode? = nil,
        petMood: Int = PetMood.happy.rawValue,
        inviteCode: String? = nil
    ) {
        self.avatar = avatar
        self.name = name
        self.squadName = squadName
        self.squadmates = squadmates
        self.minutes = minutes
        self.streak = streak
        self.pet = pet
        self.petMood = petMood
        self.inviteCode = inviteCode
    }

    /// A Plus squad is 6: you and five others.
    public static let maxLocklings = 6

    /// The id your own Lockling has in `lineup`.
    public static let youID = "you"

    /// It was a squad's session.
    public var isSquad: Bool {
        squadName != nil || !squadmates.isEmpty
    }

    /// The Locklings on the card: you first, then up to five squadmates.
    public var lineup: [Member] {
        let you = Member(id: Self.youID, name: name.flatMap(Self.cleaned) ?? "You", avatar: avatar)
        return [you] + squadmates.prefix(Self.maxLocklings - 1)
    }

    // MARK: - Words

    // English only until the app has a string catalogue.

    /// The big number: whole minutes, never negative.
    public var minutesNumber: String {
        "\(max(0, minutes))"
    }

    /// Under the number: "minutes locked in", "minute locked in together".
    public var minutesLine: String {
        let unit = max(0, minutes) == 1 ? "minute" : "minutes"
        return isSquad ? "\(unit) locked in together" : "\(unit) locked in"
    }

    /// "3-day streak", or nil with no streak to show.
    public var streakLine: String? {
        guard streak > 0 else { return nil }
        return "\(streak)-day streak"
    }

    /// "Teen sprout", "Egg", "Prestige ember". Nil with no pet.
    public var petLine: String? {
        guard let pet else { return nil }
        guard pet.growth != .egg else { return "Egg" }
        let stage = pet.stageName.prefix(1).uppercased() + String(pet.stageName.dropFirst())
        return "\(stage) \(pet.species)"
    }

    /// The invitation along the bottom.
    public static let inviteLine = "Lock in with me on Lockin"

    /// The friend code as it's printed: upper case, letters and digits only. Nil when there's
    /// nothing left to print.
    public var printedCode: String? {
        guard let inviteCode else { return nil }
        let code = inviteCode.uppercased().filter { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
        return code.isEmpty ? nil : code
    }

    /// A name trimmed and kept short enough to sit under a Lockling.
    private static func cleaned(_ name: String) -> String? {
        let trimmed = LiveActivityLimits.fittedName(name)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The two shapes a card comes in.
public enum ShareCardKind: String, CaseIterable, Sendable, Identifiable {
    /// 9:16, for Stories.
    case story
    /// 1:1, for a post or a message.
    case square

    public var id: String { rawValue }

    /// In points, which are pixels: `ShareCardRenderer` renders at scale 1.
    public var size: CGSize {
        switch self {
        case .story: CGSize(width: 1_080, height: 1_920)
        case .square: CGSize(width: 1_080, height: 1_080)
        }
    }
}
