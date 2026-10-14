import Creature
import DesignSystem
import Model
import SwiftUI

/// Made-up Locklings for the pitch, the squads teaser and snapshots.
///
/// Parts are picked from `CreatureCatalogue` by position rather than written as codes, so the
/// samples only ever use parts this build can draw, however the catalogue grows.
enum SampleLocklings {
    struct Friend: Identifiable, Sendable {
        let id: String
        let name: String
        let avatar: AvatarCode
        /// Time left on their timer when the view appears.
        let secondsLeft: TimeInterval
    }

    /// Three friends mid-session: the island the app is built around.
    static var friends: [Friend] {
        [
            Friend(id: "ava", name: "Ava", avatar: avatar(body: 1, colour: 1, eyes: 1, hat: 1, includingPlus: true), secondsLeft: 18 * 60 + 24),
            Friend(id: "noor", name: "Noor", avatar: avatar(body: 2, colour: 4, eyes: 2, hat: 0, includingPlus: true), secondsLeft: 41 * 60 + 7),
            Friend(id: "kai", name: "Kai", avatar: avatar(body: 0, colour: 7, eyes: 3, hat: 2, includingPlus: true), secondsLeft: 7 * 60 + 52),
        ]
    }

    /// A Lockling made only of free parts: "you" in snapshots.
    static var you: AvatarCode {
        avatar(body: 0, colour: 2, eyes: 1, hat: 1, includingPlus: false)
    }

    /// The option at each position of its part's list, wrapping round.
    static func avatar(body: Int, colour: Int, eyes: Int, hat: Int, includingPlus: Bool) -> AvatarCode {
        AvatarCode(
            body: pick(CreatureCatalogue.bodies, body, includingPlus: includingPlus),
            colour: pick(CreatureCatalogue.colours, colour, includingPlus: includingPlus),
            eyes: pick(CreatureCatalogue.eyes, eyes, includingPlus: includingPlus),
            hat: pick(CreatureCatalogue.hats, hat, includingPlus: includingPlus)
        )
    }

    private static func pick(_ options: [CreatureOption], _ index: Int, includingPlus: Bool) -> Int {
        let free = options.filter { !$0.isPlus }
        let pool = includingPlus || free.isEmpty ? options : free
        guard !pool.isEmpty else { return 0 }
        return pool[index % pool.count].id
    }
}

/// A Lockling on a soft circle of its own colour: the hero of most screens.
struct LocklingHero: View {
    enum Backdrop {
        /// A flat, pale disc: the creature editor, where the colour is the point.
        case disc
        /// A glow that fades out: Home and the session, where it shouldn't look like a button.
        case halo
    }

    let avatar: AvatarCode
    let pose: CreaturePose
    let size: CGFloat
    var backdrop: Backdrop = .disc

    var body: some View {
        let colour = CreatureCatalogue.colour(avatar.colour)
        let side = size * 1.3
        CreatureView(avatar: avatar, pose: pose, size: size)
            .frame(width: side, height: side)
            .background {
                switch backdrop {
                case .disc:
                    Circle()
                        .fill(colour.opacity(0.16))
                case .halo:
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colour.opacity(0.32), colour.opacity(0)],
                                center: .center,
                                startRadius: size * 0.15,
                                endRadius: side * 0.62
                            )
                        )
                        .frame(width: side * 1.25, height: side * 1.25)
                }
            }
            .animation(.smooth, value: avatar.colour)
    }
}

/// A short bounce when `trigger` changes: a Lockling reacting to being poked or dressed. Skipped
/// with Reduce Motion.
struct BumpEffect<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.08, duration: 0.12)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
            }
        }
    }
}

extension View {
    func bump(on trigger: some Equatable) -> some View {
        modifier(BumpEffect(trigger: trigger))
    }
}
