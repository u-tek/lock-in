import DesignSystem
import Foundation
import Model

/// What the Live Activity shows, worked out from its attributes and one content-state.
///
/// The views only lay this out. Keeping the decisions here (who appears where, which timers run,
/// what the compact island says) means they're tested without rendering anything, and the widget
/// extension and the app's Live Activity Lab can't disagree.
///
/// Nothing here reads the clock. The system renders a Live Activity once per update and then
/// shows it for minutes or hours, so running timers are handed to `Text(timerInterval:)` and
/// `ProgressView(timerInterval:)`, which tick on the device, rather than worked out here.
public struct LiveActivityPresentation: Hashable, Sendable {
    /// Members on the Lock Screen: a full Plus squad (SPEC.md §1.3).
    public static let lockScreenLimit = LiveActivityLimits.maxMembers
    /// Squadmates in the expanded island's bottom row. `primary` already sits beside the camera
    /// in the leading and trailing regions, so isn't one of them.
    public static let expandedLimit = 4

    /// No squad name: the solo layouts, which show `primary` alone.
    public let isSolo: Bool
    /// Everyone in the content-state, `me` first, then in server order (host first). A member id
    /// the server repeated appears once.
    public let members: [Member]
    /// Who the compact, minimal, leading and trailing presentations follow: `me`, or the host
    /// while `me` isn't in the content-state yet (a join the server hasn't pushed). Nil only when
    /// the content-state has no members at all.
    public let primary: Member?
    /// The Lock Screen's squad row: everyone, up to `lockScreenLimit`.
    public let lockScreenMembers: [Member]
    /// The expanded island's row: squadmates other than `primary`, up to `expandedLimit`.
    public let expandedMembers: [Member]
    /// Squadmates left out of `expandedMembers`, shown as "+2".
    public let expandedOverflow: Int
    /// Squadmates other than `primary` who are focusing right now: the "+3" in the compact island.
    public let othersFocusing: Int
    /// Everyone focusing right now, `primary` included.
    public let focusingCount: Int
    /// The squad name; for a solo session, what you're doing ("Locked in").
    public let headline: String
    /// "2 of 6 locked in", or "Solo session".
    public let statusLine: String
    /// The right-hand side of the compact island.
    public let compactTrailing: CompactTrailing
    /// VoiceOver's reading of `compactTrailing`. A running countdown also gets the live time as
    /// its accessibility value.
    public let compactTrailingAccessibilityLabel: String
    /// `primary`'s session as a bar, for the solo layouts.
    public let sessionProgress: SessionProgress
    /// The squad pet, when the content-state carries one. It doesn't for a solo session, or for a
    /// squad whose egg hasn't hatched.
    public let pet: Pet?

    public init(attributes: LockinAttributes, state: LockinAttributes.ContentState) {
        var seen = Set<String>()
        let members = state.ordered(meFirst: attributes.me)
            .filter { seen.insert($0.i).inserted }
            .map { Member($0, isMe: $0.i == attributes.me) }
        let primary = members.first
        let others = Array(members.dropFirst())
        let othersFocusing = others.filter { $0.state == .focusing }.count
        let focusingCount = members.filter { $0.state == .focusing }.count
        let isSolo = attributes.isSolo

        self.isSolo = isSolo
        self.members = members
        self.primary = primary
        lockScreenMembers = Array(members.prefix(Self.lockScreenLimit))
        expandedMembers = Array(others.prefix(Self.expandedLimit))
        expandedOverflow = max(0, others.count - Self.expandedLimit)
        self.othersFocusing = othersFocusing
        self.focusingCount = focusingCount
        pet = state.p.map(Pet.init)
        sessionProgress = Self.sessionProgress(for: primary)

        if isSolo {
            headline = Self.soloHeadline(for: primary?.state)
            statusLine = "Solo session"
        } else {
            let squadName = attributes.sq.map(LiveActivityLimits.fittedSquadName) ?? ""
            headline = squadName.isEmpty ? "Your squad" : squadName
            statusLine = "\(focusingCount) of \(members.count) locked in"
        }

        // "+0" says nothing, so with no squadmate focusing the compact island shows your own time.
        if !isSolo, othersFocusing > 0 {
            compactTrailing = .squadmates(othersFocusing)
            compactTrailingAccessibilityLabel = Self.squadmatesPhrase(othersFocusing)
        } else if let primary {
            compactTrailing = .countdown(primary.countdown, tone: primary.tone)
            compactTrailingAccessibilityLabel = primary.accessibilityLabel
        } else {
            compactTrailing = .empty
            compactTrailingAccessibilityLabel = ""
        }
    }

    /// The look of a member state. One-to-one, written out so a state added to Model without a
    /// look here fails to compile rather than drawing as something else.
    public static func tone(for state: MemberState) -> LKMemberTone {
        switch state {
        case .focusing: return .focusing
        case .onBreak: return .onBreak
        case .paused: return .paused
        case .done: return .done
        case .left: return .left
        case .slipped: return .slipped
        }
    }
}

// MARK: - Member

extension LiveActivityPresentation {
    /// One squad member as drawn: a badge, a name and a countdown.
    public struct Member: Hashable, Sendable, Identifiable {
        public let id: String
        /// The display name held to the wire limit, or "Someone" when the server sent none.
        public let name: String
        /// What the badge shows until creatures arrive (M1): the name's first character.
        public let initial: String
        /// A state from a newer server reads as `.focusing` (see `Member.state` in Model).
        public let state: MemberState
        public let tone: LKMemberTone
        /// For the `Creature` renderer (M1).
        public let avatar: AvatarCode
        public let isMe: Bool
        public let countdown: Countdown
        /// "Ava, you, focusing" or "Kai, paused, 13 minutes left". A running countdown isn't in
        /// the label: the views give VoiceOver the live time as the value.
        public let accessibilityLabel: String

        public init(_ member: LockinAttributes.ContentState.Member, isMe: Bool) {
            let fitted = LiveActivityLimits.fittedName(member.n)
            let name = fitted.isEmpty ? "Someone" : fitted
            let state = member.state
            let tone = LiveActivityPresentation.tone(for: state)
            let countdown = Countdown(member, tone: tone)

            var label = [name]
            if isMe {
                label.append("you")
            }
            label.append(tone.title.lowercased())
            if let remaining = countdown.frozenRemaining {
                label.append(LiveActivityPresentation.remainingPhrase(remaining))
            }

            id = member.i
            self.name = name
            initial = LiveActivityPresentation.initial(of: name)
            self.state = state
            self.tone = tone
            avatar = member.avatar
            self.isMe = isMe
            self.countdown = countdown
            accessibilityLabel = label.joined(separator: ", ")
        }
    }

    /// How a member's time is shown.
    public enum Countdown: Hashable, Sendable {
        /// Counting down on the device over `start...end`: `Text(timerInterval:)` ticks with no
        /// pushes. Focusing and on a break.
        case running(ClosedRange<Date>)
        /// Frozen at `pausedAt`, which lies inside the range: `Text(timerInterval:pauseTime:)`
        /// shows `end - pausedAt` and stays there.
        case paused(ClosedRange<Date>, pausedAt: Date)
        /// No timer, a word: done, left and slipped, and a pause the server sent no time for.
        case text(String)

        init(_ member: LockinAttributes.ContentState.Member, tone: LKMemberTone) {
            let range = member.timerRange
            switch member.state {
            case .focusing, .onBreak:
                self = .running(range)
            case .paused:
                if let pausedAt = member.q, pausedAt.isFinite {
                    let date = Date(timeIntervalSince1970: pausedAt)
                    self = .paused(range, pausedAt: min(max(date, range.lowerBound), range.upperBound))
                } else {
                    self = .text(tone.title)
                }
            case .done, .left, .slipped:
                // Slipped ends the member's timer, as `MemberState.isActive` has it (M8 may revisit).
                self = .text(tone.title)
            }
        }

        public var range: ClosedRange<Date>? {
            switch self {
            case .running(let range), .paused(let range, _): return range
            case .text: return nil
            }
        }

        public var pausedAt: Date? {
            guard case .paused(_, let pausedAt) = self else { return nil }
            return pausedAt
        }

        /// The word shown instead of a timer.
        public var staticText: String? {
            guard case .text(let text) = self else { return nil }
            return text
        }

        /// Seconds a paused timer shows. Nil unless paused.
        public var frozenRemaining: TimeInterval? {
            guard case .paused(let range, let pausedAt) = self else { return nil }
            return max(0, range.upperBound.timeIntervalSince(pausedAt))
        }

        /// Whether the timer can show an hour or more ("1:29:59" rather than "24:59").
        public var needsHours: Bool {
            switch self {
            case .running(let range): return range.upperBound.timeIntervalSince(range.lowerBound) >= 3_600
            case .paused: return (frozenRemaining ?? 0) >= 3_600
            case .text: return false
            }
        }

        /// Width to reserve for the timer in a font of `fontSize` points, or nil for a word, which
        /// takes its own width.
        ///
        /// `Text(timerInterval:)` asks for all the width it's offered, which in the compact island
        /// would push the island wide, so timers get a fixed frame sized for their longest
        /// reading. Monospaced digits are about 0.62 em and a colon about 0.32 em, so "24:59" is
        /// about 2.8 em and "1:29:59" about 3.75; the frames round up from there.
        public func reservedWidth(fontSize: CGFloat) -> CGFloat? {
            guard staticText == nil else { return nil }
            return (fontSize * (needsHours ? 4 : 3)).rounded(.up)
        }
    }

    /// The right-hand side of the compact island (SPEC.md §1.3).
    public enum CompactTrailing: Hashable, Sendable {
        /// Squadmates focusing right now, as "+3".
        case squadmates(Int)
        /// Your own time: solo, or when no squadmate is focusing.
        case countdown(Countdown, tone: LKMemberTone)
        /// An empty content-state.
        case empty

        /// "+3", a word, or nil for a running or paused timer.
        public var staticText: String? {
            switch self {
            case .squadmates(let count): return "+\(count)"
            case .countdown(let countdown, _): return countdown.staticText
            case .empty: return nil
            }
        }
    }

    /// A session as a bar.
    public enum SessionProgress: Hashable, Sendable {
        /// Filling on the device over the range: `ProgressView(timerInterval:countsDown: false)`.
        case live(ClosedRange<Date>)
        /// A fixed fraction, 0...1: paused, or done (1).
        case fixed(Double)
        /// Nothing to show: left or slipped, or no member.
        case hidden
    }

    /// The squad pet, as drawn until the real one arrives (`Creature` in M1, moods and stages in M5).
    public struct Pet: Hashable, Sendable {
        public let code: PetCode
        /// 0 (lowest) to 3 (happiest).
        public let mood: Int
        /// Progress to the next stage, 0...1.
        public let progress: Double
        /// "Fox · teen".
        public let title: String
        public let accessibilityLabel: String

        public init(_ pet: LockinAttributes.ContentState.Pet) {
            let code = pet.code
            let species = code.species.prefix(1).uppercased() + String(code.species.dropFirst())
            let stage: String
            switch code.growth {
            case .egg: stage = "egg"
            case .baby: stage = "baby"
            case .teen: stage = "teen"
            case .adult: stage = "adult"
            case .prestige: stage = "prestige \(code.prestigeLevel)"
            }
            // Rounded down, so it never says 100 before the pet grows.
            let percent = Int((pet.progress * 100).rounded(.down))

            self.code = code
            mood = pet.mood
            progress = pet.progress
            title = "\(species) · \(stage)"
            accessibilityLabel = "Squad pet, \(code.species), \(stage), \(percent) percent of the way to the next stage"
        }
    }
}

// MARK: - Wording

// English only until the app has a string catalogue, like `LKMemberTone.title`.
extension LiveActivityPresentation {
    /// The solo headline for what you're doing.
    static func soloHeadline(for state: MemberState?) -> String {
        guard let state else { return "Session" }
        switch state {
        case .focusing: return "Locked in"
        case .onBreak: return "On a break"
        case .paused: return "Paused"
        case .done: return "Session done"
        case .left: return "Ended early"
        case .slipped: return "Slipped"
        }
    }

    /// "1 squadmate locked in", "3 squadmates locked in".
    static func squadmatesPhrase(_ count: Int) -> String {
        count == 1 ? "1 squadmate locked in" : "\(count) squadmates locked in"
    }

    /// "13 minutes left", "1 hour 5 minutes left", "under a minute left". Whole minutes, rounded
    /// down, like the timer beside it.
    static func remainingPhrase(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "under a minute left" }
        // Held well inside Int's range: a broken end time can be any Double.
        let totalMinutes = Int(min(seconds, 1_000_000_000) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        return parts.joined(separator: " ") + " left"
    }

    /// The first character that isn't whitespace, uppercased; "?" for a blank name. A whole
    /// character, so an emoji or an accented letter stays in one piece.
    static func initial(of name: String) -> String {
        guard let first = name.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }

    static func sessionProgress(for member: Member?) -> SessionProgress {
        guard let member else { return .hidden }
        switch member.countdown {
        case .running(let range):
            // A zero-length timer has nothing to fill.
            return range.lowerBound < range.upperBound ? .live(range) : .fixed(1)
        case .paused(let range, let pausedAt):
            let span = range.upperBound.timeIntervalSince(range.lowerBound)
            guard span > 0 else { return .fixed(1) }
            return .fixed(min(max(pausedAt.timeIntervalSince(range.lowerBound) / span, 0), 1))
        case .text:
            return member.state == .done ? .fixed(1) : .hidden
        }
    }
}
