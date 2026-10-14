import Creature
import SwiftUI

/// A squad member as their Lockling, in the pose for their state: focusing behind a book, on a
/// break with a mug, paused asleep, done with the shackle popped open, greyed out and waving when
/// they've left, sweating when they slipped. The pose carries the state, so colour is never the
/// only cue (design/SYSTEM.md).
///
/// It fills a `size` square and draws no background, so it sits on the Lock Screen's default
/// background in either appearance and on the island's black. In Always-On the Lockling turns
/// itself into an outline. One VoiceOver element that names the member and their state.
public struct MemberBadge: View {
    private let member: LiveActivityPresentation.Member
    private let size: CGFloat

    public init(_ member: LiveActivityPresentation.Member, size: CGFloat) {
        self.member = member
        self.size = size
    }

    public var body: some View {
        CreatureView(avatar: member.avatar, pose: CreaturePose(member.state), size: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(member.accessibilityLabel)
    }
}
