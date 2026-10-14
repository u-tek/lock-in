import DesignSystem
import Model
import SessionEngine
import ShareCards
import SwiftUI

/// Share on the finished screen (SPEC.md §1.7): the 9:16 story card through the share sheet, or,
/// from a long press, the 1:1 square. The cards are drawn when the share sheet asks for them
/// (`ShareCardImage`), not every time the screen is.
struct ShareCardButton: View {
    let card: ShareCard

    var body: some View {
        let story = ShareCardImage(card: card, kind: .story)
        let square = ShareCardImage(card: card, kind: .square)
        ShareLink(item: story, preview: SharePreview(Self.title, image: story)) {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(LKFont.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .lkSecondaryButton()
        .contextMenu {
            ShareLink(item: story, preview: SharePreview(Self.title, image: story)) {
                Label("Share for Stories", systemImage: "rectangle.portrait")
            }
            ShareLink(item: square, preview: SharePreview(Self.title, image: square)) {
                Label("Share as a Square", systemImage: "square")
            }
        }
    }

    private static let title = "My Lockin session"
}

extension ShareCard {
    /// The card for a finished session: yours, or, after a squad's, the squad that just finished
    /// together, with its pet. Nobody else's name is on it, and nobody who left the room early.
    /// Nil when there's nothing to show off: less than a minute.
    ///
    /// - Parameters:
    ///   - myName: Your display name, when signed in; a squad's room has its own for you.
    ///   - inviteCode: Your friend code, for "Lock in with me on Lockin".
    init?(record: SessionRecord, avatar: AvatarCode, streak: Int, squad: SquadSessionInfo?, myName: String?, inviteCode: String?) {
        let minutes = record.completed ? record.plannedMinutes : record.focusedMinutes
        guard minutes >= 1 else { return nil }
        self.init(avatar: avatar, name: myName, minutes: minutes, streak: streak, inviteCode: inviteCode)
        guard let squad else { return }
        squadName = squad.name ?? "My squad"
        squadmates = squad.others
            .filter { $0.state != .left }
            .map { Member(id: $0.i, name: $0.n, avatar: $0.avatar) }
        if let me = squad.member(id: squad.me) {
            name = me.n
        }
        if let pet = squad.room.p {
            self.pet = pet.code
            petMood = pet.mood
        }
    }
}
