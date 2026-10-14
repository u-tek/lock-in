import API
import Foundation

extension FriendCode {
    /// The characters codes are made of: no 0/O or 1/I, so a code read aloud or off a screen
    /// can't be misread.
    public static let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    public static let length = 8

    private static let allowed = Set(alphabet.unicodeScalars)

    /// A code as typed or pasted, tidied: uppercase, without spaces or dashes ("kq7m-2xpa" and
    /// "KQ7M 2XPA" are both "KQ7M2XPA").
    public static func normalised(_ input: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in input.uppercased().unicodeScalars where !isSeparator(scalar) {
            kept.append(scalar)
        }
        return String(kept)
    }

    /// Spaces, and dashes of every kind people paste ("‐", "‑", "–" as well as "-").
    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}"].contains(scalar)
    }

    /// Exactly 8 characters of the alphabet, after `normalised(_:)`.
    public static func isWellFormed(_ code: String) -> Bool {
        let scalars = Array(code.unicodeScalars)
        return scalars.count == length && scalars.allSatisfy { allowed.contains($0) }
    }

    /// The code split in two for reading: "KQ7M 2XPA".
    public static func spaced(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(length / 2)) \(code.suffix(length / 2))"
    }
}

/// An invite link: `lockin://j/<code>` (opens the app) or `https://<invite host>/j/<code>` (the
/// landing page, or the app once universal links are set up in M9).
public struct InviteLink: Hashable, Sendable {
    /// Normalised and well formed.
    public let code: String

    public static let scheme = "lockin"
    /// The path segment both forms share.
    static let segment = "j"

    public init?(code: String) {
        let normalised = FriendCode.normalised(code)
        guard FriendCode.isWellFormed(normalised) else { return nil }
        self.code = normalised
    }

    /// Reads either form. Any https host is accepted: a link only reaches the app from a domain
    /// it's associated with, and a pasted one carries nothing but a code the server checks.
    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let parts: [String]
        switch scheme {
        case Self.scheme:
            // lockin://j/CODE: "j" is the host.
            guard url.host(percentEncoded: false)?.lowercased() == Self.segment else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        case "https", "http":
            let path = url.pathComponents.filter { $0 != "/" }
            guard path.count >= 2, path[0].lowercased() == Self.segment else { return nil }
            parts = Array(path.dropFirst())
        default:
            return nil
        }
        guard parts.count == 1 else { return nil }
        self.init(code: parts[0])
    }

    /// A code or a link, from whatever was pasted: "KQ7M-2XPA", or a message with a link in it.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = InviteLink(code: trimmed) {
            self = direct
            return
        }
        for word in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            if let url = URL(string: String(word)), let link = InviteLink(url: url) {
                self = link
                return
            }
        }
        return nil
    }

    /// `lockin://j/<code>`.
    public var appURL: URL {
        URL(string: "\(Self.scheme)://\(Self.segment)/\(code)")!
    }

    /// The link to share: the server's own for the code (`FriendCode.url`), so the host it names
    /// is always the one serving the landing page.
    public static func shareURL(for code: FriendCode) -> URL {
        code.url
    }

    /// What goes out with the link.
    public static let shareMessage = "Lock in with me on Lockin"
}
