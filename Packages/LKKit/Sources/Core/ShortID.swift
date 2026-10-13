import Foundation

/// Short ids: 10 base62 characters (`[0-9A-Za-z]`), the shape the server uses for sessions,
/// members and squads.
///
/// They're short because every byte of a Live Activity payload counts (SPEC.md §4.3). 62^10 is
/// about 8 × 10^17, so random ids don't collide at any size this app will reach. The server makes
/// the shared ones; these are for things that only exist on this phone, like a solo session.
public enum ShortID {
    public static let length = 10
    public static let alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    private static let characters = Array(alphabet)

    /// A new id drawn from `generator`. Tests pass a seeded generator to get repeatable ids.
    public static func make<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        var id = ""
        id.reserveCapacity(length)
        for _ in 0..<length {
            id.append(characters[Int.random(in: 0..<characters.count, using: &generator)])
        }
        return id
    }

    /// A new id from the system's secure random source.
    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    /// Exactly 10 ASCII letters and digits. Ids from the server are checked before they're used
    /// as file names or keys.
    public static func isValid(_ id: String) -> Bool {
        id.utf8.count == length && id.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
        }
    }
}
