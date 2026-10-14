import API
import Creature
import DesignSystem
import Model
import Social
import SwiftUI

// Pieces the squad screens share: a member's name, overlapping Locklings, the list row, the
// egg the new-squad sheet shows, and what squad errors say.

extension SquadMember {
    /// What to call them: display name, else handle, else "Lockling" (the server's rule for the
    /// Live Activity's names).
    var nameForDisplay: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let handle, !handle.isEmpty { return handle }
        return "Lockling"
    }

    var locklingAvatar: AvatarCode {
        AvatarCode(avatarCode)
    }
}

/// Up to `limit` members' Locklings, overlapping like a stack of faces. Each sits on a ring of
/// `ringColour`, so they read apart where they overlap.
struct SquadLocklings: View {
    let members: [SquadMember]
    var size: CGFloat = 36
    var limit = 4
    var pose: CreaturePose = .idle
    /// The surface they sit on: the list row's colour by default.
    var ringColour = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        let shown = Array(members.prefix(limit))
        HStack(spacing: -size * 0.28) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, member in
                FriendAvatar(avatar: member.locklingAvatar, pose: pose, size: size)
                    .padding(2)
                    .background(Circle().fill(ringColour))
                    // The first on top, like a row of people standing in front of each other.
                    .zIndex(Double(shown.count - index))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A squad in the Friends list: its Locklings, its name, and whether it's locked in right now.
struct SquadRow: View {
    let squad: Squad

    var body: some View {
        HStack(spacing: LKSpacing.m) {
            SquadLocklings(members: squad.members, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(squad.name)
                    .font(LKFont.body.weight(.semibold))
                if squad.openSessionId != nil {
                    Label("Locked in now", systemImage: "lock.fill")
                        .font(LKFont.subheadline.weight(.medium))
                        .foregroundStyle(LKColor.focusing)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(memberCount)
                        .font(LKFont.subheadline)
                        .foregroundStyle(LKColor.textSecondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, LKSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var memberCount: String {
        squad.members.count == 1 ? "Just you so far" : "\(squad.members.count) members"
    }
}

/// A new squad: your Lockling hugging the squad's egg (the pet hatches from it after the first
/// session together), with two faded Locklings waving in for the friends you'll invite.
struct SquadHatchery: View {
    let avatar: AvatarCode
    var size: CGFloat = 220

    var body: some View {
        let colour = CreatureCatalogue.colour(avatar.colour)
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [colour.opacity(0.28), colour.opacity(0)],
                    center: .center,
                    startRadius: size * 0.08,
                    endRadius: size * 0.55
                ))
                .frame(width: size * 1.1, height: size * 1.1)
            friend(AvatarCode(body: 1, colour: 4, eyes: 2, hat: 0))
                .offset(x: -size * 0.36, y: size * 0.04)
            friend(AvatarCode(body: 2, colour: 1, eyes: 1, hat: 0))
                .offset(x: size * 0.36, y: size * 0.04)
            SquadEgg()
                .frame(width: size * 0.3, height: size * 0.38)
                .offset(y: -size * 0.12)
            CreatureView(avatar: avatar, pose: .celebrating, size: size * 0.36)
                .offset(y: size * 0.19)
        }
        .frame(width: size, height: size * 0.8)
        .accessibilityHidden(true)
    }

    /// A friend still to come: greyed and waving (the `left` pose), smaller and further back.
    private func friend(_ avatar: AvatarCode) -> some View {
        CreatureView(avatar: avatar, pose: .left, size: size * 0.24)
    }
}

/// The squad pet's egg: cream, speckled, with a soft shine.
struct SquadEgg: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                EggShape()
                    .fill(LinearGradient(
                        colors: [Color.orange.mix(with: .white, by: 0.85), Color.orange.mix(with: .white, by: 0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                ForEach(Self.speckles.indices, id: \.self) { index in
                    let speckle = Self.speckles[index]
                    Circle()
                        .fill(Color.orange.opacity(0.4))
                        .frame(width: w * speckle.size, height: w * speckle.size)
                        .position(x: w * speckle.x, y: h * speckle.y)
                }
                Ellipse()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: w * 0.16, height: h * 0.18)
                    .rotationEffect(.degrees(-24))
                    .position(x: w * 0.3, y: h * 0.28)
            }
            .clipShape(EggShape())
        }
    }

    private struct Speckle {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
    }

    private static let speckles: [Speckle] = [
        Speckle(x: 0.62, y: 0.3, size: 0.09),
        Speckle(x: 0.38, y: 0.55, size: 0.07),
        Speckle(x: 0.7, y: 0.62, size: 0.11),
        Speckle(x: 0.5, y: 0.8, size: 0.06),
        Speckle(x: 0.24, y: 0.72, size: 0.08),
    ]
}

/// An egg, wider towards the bottom.
struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.62),
            control1: CGPoint(x: rect.midX + w * 0.42, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.88),
            control2: CGPoint(x: rect.midX + w * 0.28, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + h * 0.62),
            control1: CGPoint(x: rect.midX - w * 0.28, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.3),
            control2: CGPoint(x: rect.midX - w * 0.42, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Errors

extension Error {
    /// A free limit was hit (`402 plus_required`): a squad count or a squad's size. The moment
    /// for Lockin Plus (SPEC.md §2, paywall moment 2), never an error alert.
    var hitsFreeLimit: Bool {
        guard let error = self as? APIError else { return false }
        return error.status == 402 || error.code?.rawValue == "plus_required"
    }

    /// What a failed squad or session request says: short and warm. Codes the M2 client doesn't
    /// know yet are worded here; anything else is the client's own sentence.
    var squadMessage: String {
        guard let error = self as? APIError else {
            return "Something went wrong. Please try again."
        }
        switch error.code?.rawValue ?? "" {
        case "name_invalid": return "Squad names are 1 to 20 characters."
        case "name_not_allowed": return "Please pick another name."
        case "already_member": return "You're already in this squad."
        case "not_member": return "You're not in that squad any more."
        case "code_not_found": return "That code doesn't exist. Check it and try again."
        case "code_expired": return "That code has expired. Ask for a new one."
        case "blocked": return "You can't join this squad."
        case "already_in_session": return "You're already locked in."
        case "room_full": return "That room's full right now."
        case "session_ended", "session_not_found": return "That session has finished."
        case "minutes_invalid": return "Pick a length up to 4 hours."
        case "cheer_too_soon": return "One cheer at a time. Try again in a moment."
        case "try_again": return "Lockin's busy. Please try again."
        default: return error.localizedDescription
        }
    }
}
