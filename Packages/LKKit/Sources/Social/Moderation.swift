import Foundation

/// The handle and display-name check, mirroring the server's (`fixtures/moderation/README.md`).
///
/// The server is the authority; this runs in the handle picker so a bad name is caught as it's
/// typed. The words are compiled in (the package has no resources) and `SocialTests` compares
/// them with `fixtures/moderation/words.json`, and runs every case in `cases.json`, so the two
/// sides can't drift.
public enum Moderation {
    public enum Verdict: String, Sendable, CaseIterable {
        case ok
        case invalid
        case notAllowed = "not_allowed"
    }

    public enum Kind: String, Sendable {
        case handle
        case name
    }

    /// Handles: 3–20 characters.
    public static let handleLength = 3...20
    /// Display names: 1–12 code points, the Live Activity's `n`.
    public static let nameLength = 1...12

    public static func check(_ input: String, as kind: Kind) -> Verdict {
        switch kind {
        case .handle: checkHandle(input)
        case .name: checkName(input)
        }
    }

    /// 3–20 of `a-z 0-9 _ .`, starting with a letter, after lowercasing; then the word lists.
    public static func checkHandle(_ input: String) -> Verdict {
        let lowered = input.lowercased()
        guard isValidHandle(lowered) else { return .invalid }
        return isAllowed(lowered) ? .ok : .notAllowed
    }

    /// 1–12 code points after trimming, no control characters; then the word lists.
    public static func checkName(_ input: String) -> Verdict {
        let name = trimmed(input)
        guard nameLength.contains(name.unicodeScalars.count),
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return .invalid }
        return isAllowed(name.lowercased()) ? .ok : .notAllowed
    }

    /// What's typed into the handle field, tidied as it's typed: lowercase, without a leading "@"
    /// or any whitespace. Anything else stays, so the field can say what's wrong with it.
    public static func cleanHandleInput(_ input: String) -> String {
        var cleaned = input.lowercased().filter { !$0.isWhitespace }
        while cleaned.hasPrefix("@") {
            cleaned.removeFirst()
        }
        return cleaned
    }

    /// A display name as it's saved: trimmed the way the server trims.
    public static func trimmed(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, isTrimmable(scalars[start]) {
            start += 1
        }
        while end > start, isTrimmable(scalars[end - 1]) {
            end -= 1
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start..<end])
        return String(view)
    }

    // MARK: - The algorithm

    static func isValidHandle(_ lowered: String) -> Bool {
        let scalars = Array(lowered.unicodeScalars)
        guard handleLength.contains(scalars.count), let first = scalars.first, isLetter(first) else { return false }
        return scalars.allSatisfy { isLetter($0) || isDigit($0) || $0 == "_" || $0 == "." }
    }

    /// Steps 2 and 3: leet letters swapped in, split into a-z tokens, then the three lists.
    static func isAllowed(_ lowered: String) -> Bool {
        let (tokens, compact) = normalise(lowered)
        let words = ModerationWords.self
        if words.anywhere.contains(where: { compact.contains($0) }) {
            return false
        }
        for word in tokens + [compact] where words.token.contains(word) || words.reserved.contains(word) {
            return false
        }
        return true
    }

    /// The tokens of a lowercased input and their concatenation (the compact form).
    static func normalise(_ lowered: String) -> (tokens: [String], compact: String) {
        var tokens: [String] = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            let mapped = ModerationWords.leet[scalar] ?? scalar
            if isLetter(mapped) {
                current.unicodeScalars.append(mapped)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return (tokens, tokens.joined())
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    /// JavaScript's `String.prototype.trim()` set (whitespace and line terminators), which the
    /// server uses. Foundation's `.whitespacesAndNewlines` differs at U+0085 and U+FEFF.
    private static func isTrimmable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            true
        default:
            false
        }
    }
}

/// `fixtures/moderation/words.json`, compiled in. Edit both together; `SocialTests` fails when
/// they differ.
enum ModerationWords {
    static let version = 1

    static let leet: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "o",
        "1": "i",
        "3": "e",
        "4": "a",
        "5": "s",
        "7": "t",
        "8": "b",
        "9": "g",
        "@": "a",
        "$": "s",
        "!": "i",
        "|": "i",
        "+": "t",
    ]

    static let anywhere: [String] = [
        "fuck", "shit", "cunt", "bitch", "nigger", "nigga", "faggot", "retard", "whore", "slut",
        "penis", "vagina", "nazi", "porn", "killyourself", "twat", "wank", "bastard", "asshole",
        "dildo", "jizz", "tranny", "motherfucker", "cocksucker", "hitler",
    ]

    static let token: Set<String> = [
        "ass", "arse", "hell", "damn", "tit", "tits", "cum", "dick", "cock", "pussy", "rape", "sex",
        "fag", "spic", "chink", "kike", "coon", "paki", "dyke", "kys", "hoe", "nude", "nudes",
        "boob", "boobs",
    ]

    static let reserved: Set<String> = [
        "admin", "administrator", "lockin", "lockinapp", "support", "help", "official", "staff",
        "moderator", "mod", "apple", "system", "root", "null", "undefined", "everyone", "demo",
        "demobuddy", "team",
    ]
}
