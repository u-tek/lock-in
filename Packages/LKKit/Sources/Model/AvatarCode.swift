import Foundation

/// A creature's look, as carried in `Member.a`: `b<body>.c<colour>.e<eyes>.h<hat>`, e.g.
/// "b3.c7.e2.h4" (SPEC.md §5.3).
///
/// Parsing never fails. Another member's code may come from a newer app version with parts this
/// one doesn't know, so: parts can come in any order, unknown letters are skipped, and a missing
/// or garbled part reads as 0, the default. Indices beyond what this version can draw are the
/// creature renderer's to fall back from (`Creature`, M1).
public struct AvatarCode: Hashable, Sendable, CustomStringConvertible {
    public var body: Int
    public var colour: Int
    public var eyes: Int
    public var hat: Int

    public init(body: Int = 0, colour: Int = 0, eyes: Int = 0, hat: Int = 0) {
        self.body = max(0, body)
        self.colour = max(0, colour)
        self.eyes = max(0, eyes)
        self.hat = max(0, hat)
    }

    /// Reads a code leniently. For each letter the first well-formed part wins.
    public init(_ code: String) {
        var body: Int?
        var colour: Int?
        var eyes: Int?
        var hat: Int?
        for part in code.split(separator: ".") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let letter = trimmed.first, let value = Self.index(trimmed.dropFirst()) else { continue }
            switch letter {
            case "b": body = body ?? value
            case "c": colour = colour ?? value
            case "e": eyes = eyes ?? value
            case "h": hat = hat ?? value
            default: continue
            }
        }
        self.init(body: body ?? 0, colour: colour ?? 0, eyes: eyes ?? 0, hat: hat ?? 0)
    }

    /// The canonical form: every part, in order.
    public var code: String {
        "b\(body).c\(colour).e\(eyes).h\(hat)"
    }

    public var description: String {
        code
    }

    public static let `default` = AvatarCode()

    /// ASCII digits only: no signs, spaces or other scripts' numerals. Nil when it overflows.
    private static func index(_ digits: Substring) -> Int? {
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
}
