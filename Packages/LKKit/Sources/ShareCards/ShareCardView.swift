import Creature
import DesignSystem
import Model
import SwiftUI

/// A share card, drawn at its full size in points: 1080 × 1920 for a story, 1080 × 1080 for a
/// square. `ShareCardRenderer` renders it at scale 1, so a point is a pixel.
///
/// Made to be read small, on someone else's phone, in a second: the Locklings large, one huge
/// number, short lines in heavy type, white on the brand's indigo. Fixed sizes, not Dynamic Type:
/// it's a picture, the same for everyone who sees it. Always drawn dark, so system colours resolve
/// the same way whatever the phone's appearance.
///
/// A story keeps what matters inside the middle 1460 points: Instagram lays its own bars over the
/// top and bottom of a story.
public struct ShareCardView: View {
    private let kind: ShareCardKind
    private let card: ShareCard

    public init(kind: ShareCardKind, card: ShareCard) {
        self.kind = kind
        self.card = card
    }

    public var body: some View {
        ZStack {
            CardBackground(kind: kind)
            switch kind {
            case .story: StoryLayout(card: card)
            case .square: SquareLayout(card: card)
            }
        }
        .frame(width: kind.size.width, height: kind.size.height)
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.isLuminanceReduced, false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CardWords.spoken(card)))
    }
}

// MARK: - Layouts

/// Top to bottom: the wordmark, the squad's name, the Locklings, the minutes, the streak and the
/// pet, and the invitation.
private struct StoryLayout: View {
    let card: ShareCard

    var body: some View {
        VStack(spacing: 0) {
            Wordmark(height: 72)
            Spacer(minLength: 32)
            if let squadName = card.squadName {
                Text(squadName)
                    .font(.system(size: 60, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 36)
            }
            Lineup(card: card, layout: .story)
            Spacer(minLength: 32)
            BigMinutes(card: card, numberSize: 220, lineSize: 60, alignment: .center)
            Spacer(minLength: 32)
            Badges(card: card, height: 104)
            Spacer(minLength: 40)
            Invitation(card: card, size: .large)
        }
        .padding(.horizontal, 88)
        .padding(.top, 200)
        .padding(.bottom, 260)
    }
}

/// The wordmark and the streak across the top, the Locklings beside the minutes, the invitation
/// along the bottom.
private struct SquareLayout: View {
    let card: ShareCard

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Wordmark(height: 60)
                Spacer(minLength: 24)
                if let streak = card.streakLine {
                    Badge(height: 80) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text(streak)
                    }
                }
            }
            Spacer(minLength: 24)
            HStack(alignment: .center, spacing: 48) {
                Lineup(card: card, layout: .square)
                    .frame(width: 420)
                VStack(alignment: .leading, spacing: 20) {
                    if let squadName = card.squadName {
                        Text(squadName)
                            .font(.system(size: 44, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    BigMinutes(card: card, numberSize: 200, lineSize: 50, alignment: .leading)
                    if let pet = card.pet, let line = card.petLine {
                        Badge(height: 88) {
                            PetView(code: pet, mood: card.petMood, size: 64)
                            Text(line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 24)
            Invitation(card: card, size: .compact)
        }
        .padding(72)
    }
}

// MARK: - Pieces

/// The brand's indigo, deeper at the top and warming towards purple at the bottom, with a soft
/// light where the Locklings stand.
private struct CardBackground: View {
    let kind: ShareCardKind

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    LKColor.tint.mix(with: .black, by: 0.55),
                    LKColor.tint.mix(with: .black, by: 0.1),
                    LKColor.tint.mix(with: .purple, by: 0.45),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                center: kind == .story ? UnitPoint(x: 0.5, y: 0.33) : UnitPoint(x: 0.3, y: 0.5),
                startRadius: 0,
                endRadius: kind == .story ? 620 : 440
            )
        }
    }
}

/// The app's lock on a white tile, and its name.
private struct Wordmark: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: height * 0.28) {
            Image(systemName: "lock.fill")
                .font(.system(size: height * 0.5, weight: .bold))
                .foregroundStyle(LKColor.tint)
                .frame(width: height, height: height)
                .background(Color.white, in: RoundedRectangle(cornerRadius: height * 0.26, style: .continuous))
            Text("Lockin")
                .font(.system(size: height * 0.72, weight: .bold))
        }
    }
}

/// Your Lockling, or the squad's, each with a glow in its own colour; in a squad, their names
/// under them.
private struct Lineup: View {
    enum Layout {
        case story
        case square
    }

    let card: ShareCard
    let layout: Layout

    var body: some View {
        let members = card.lineup
        if !card.isSquad {
            LocklingWithGlow(avatar: card.avatar, pose: .celebrating, size: layout == .story ? 520 : 400)
        } else {
            let rows = Self.rows(of: members)
            let size = Self.size(count: members.count, layout: layout)
            VStack(spacing: layout == .story ? 28 : 20) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: layout == .story ? 24 : 16) {
                        ForEach(rows[index]) { member in
                            VStack(spacing: 8) {
                                LocklingWithGlow(
                                    avatar: member.avatar,
                                    pose: member.id == ShareCard.youID ? .celebrating : .done,
                                    size: size
                                )
                                Text(member.name)
                                    .font(.system(size: layout == .story ? 44 : 32, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: size + 16)
                            }
                        }
                    }
                }
            }
        }
    }

    /// One row up to three; two rows from four, the first as full as the second.
    static func rows(of members: [ShareCard.Member]) -> [[ShareCard.Member]] {
        guard members.count > 3 else { return [members] }
        let firstRow = (members.count + 1) / 2
        return [Array(members.prefix(firstRow)), Array(members.dropFirst(firstRow))]
    }

    /// As large as fits: the story is 904 points wide inside its margins, the square's column 420.
    static func size(count: Int, layout: Layout) -> CGFloat {
        switch layout {
        case .story:
            switch count {
            case ...2: 300
            case 3: 240
            default: 200
            }
        case .square:
            switch count {
            case ...2: 180
            case 3, 4: 160
            default: 120
            }
        }
    }
}

/// A Lockling on a glow of its own colour.
private struct LocklingWithGlow: View {
    let avatar: AvatarCode
    let pose: CreaturePose
    let size: CGFloat

    var body: some View {
        let colour = CreatureCatalogue.colour(avatar.colour)
        CreatureView(avatar: avatar, pose: pose, size: size)
            .background {
                Circle()
                    .fill(RadialGradient(
                        colors: [colour.opacity(0.55), colour.opacity(0)],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.62
                    ))
                    .frame(width: size * 1.3, height: size * 1.3)
            }
    }
}

/// "25", huge, and "minutes locked in" under it.
private struct BigMinutes: View {
    let card: ShareCard
    let numberSize: CGFloat
    let lineSize: CGFloat
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(card.minutesNumber)
                .font(.system(size: numberSize, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(card.minutesLine)
                .font(.system(size: lineSize, weight: .semibold))
                .opacity(0.88)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The streak and the pet, side by side.
private struct Badges: View {
    let card: ShareCard
    let height: CGFloat

    var body: some View {
        HStack(spacing: 24) {
            if let streak = card.streakLine {
                Badge(height: height) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text(streak)
                }
            }
            if let pet = card.pet, let line = card.petLine {
                Badge(height: height) {
                    PetView(code: pet, mood: card.petMood, size: height * 0.78)
                    Text(line)
                }
            }
        }
    }
}

/// A capsule of frosted white with a symbol or a pet, and a few words.
private struct Badge<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: height * 0.18) {
            content()
        }
        .font(.system(size: height * 0.42, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, height * 0.36)
        .frame(height: height)
        .background(Color.white.opacity(0.16), in: Capsule())
    }
}

/// "Lock in with me on Lockin" and your friend code on a white capsule; without a code, where to
/// find the app.
private struct Invitation: View {
    enum Size {
        case large
        case compact
    }

    let card: ShareCard
    let size: Size

    var body: some View {
        let isLarge = size == .large
        VStack(spacing: isLarge ? 24 : 16) {
            Text(ShareCard.inviteLine)
                .font(.system(size: isLarge ? 56 : 44, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let code = card.printedCode {
                HStack(spacing: isLarge ? 24 : 18) {
                    Text("CODE")
                        .font(.system(size: isLarge ? 30 : 24, weight: .heavy))
                        .tracking(isLarge ? 4 : 3)
                        .opacity(0.55)
                    Text(code)
                        .font(.system(size: isLarge ? 68 : 52, weight: .heavy))
                        .monospacedDigit()
                        .tracking(isLarge ? 8 : 6)
                }
                .foregroundStyle(LKColor.tint.mix(with: .black, by: 0.25))
                .lineLimit(1)
                .padding(.horizontal, isLarge ? 48 : 36)
                .padding(.vertical, isLarge ? 22 : 16)
                .background(Color.white, in: Capsule())
            } else {
                Text("Free on the App Store")
                    .font(.system(size: isLarge ? 40 : 32, weight: .semibold))
                    .opacity(0.75)
            }
        }
    }
}

/// What VoiceOver says for the card where it's shown in the app.
enum CardWords {
    static func spoken(_ card: ShareCard) -> String {
        var parts: [String] = []
        if let squadName = card.squadName {
            parts.append(squadName)
        }
        parts.append("\(card.minutesNumber) \(card.minutesLine)")
        if let streak = card.streakLine {
            parts.append(streak)
        }
        if let pet = card.petLine {
            parts.append("Squad pet: \(pet)")
        }
        if let code = card.printedCode {
            parts.append("\(ShareCard.inviteLine), code \(code)")
        }
        return parts.joined(separator: ". ")
    }
}
