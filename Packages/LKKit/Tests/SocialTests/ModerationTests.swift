import Foundation
import Testing
@testable import Social

/// `fixtures/moderation/` at the repository root. The server's tests read the same files, so the
/// app and the server can't disagree about a handle without one of them failing.
enum ModerationFixture {
    struct Words: Decodable {
        var version: Int
        var leet: [String: String]
        var anywhere: [String]
        var token: [String]
        var reserved: [String]
    }

    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        var kind: String
        var input: String
        var expected: String

        var testDescription: String {
            "\(kind) \(input.debugDescription) → \(expected)"
        }
    }

    struct NotFound: Error, CustomStringConvertible {
        var description: String
    }

    /// Walks up from this file to the directory holding `fixtures/moderation`, so the tests don't
    /// depend on how deep the package sits in the repository.
    static func directory() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in url.pathComponents.indices {
            let candidate = url.appendingPathComponent("fixtures/moderation", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        throw NotFound(description: "No fixtures/moderation above \(#filePath)")
    }

    static func words() throws -> Words {
        try JSONDecoder().decode(Words.self, from: Data(contentsOf: directory().appendingPathComponent("words.json")))
    }

    /// Read when the tests are collected, so each case shows up as its own test.
    static let cases: [Case] = {
        guard let url = try? directory().appendingPathComponent("cases.json"),
              let data = try? Data(contentsOf: url),
              let cases = try? JSONDecoder().decode([Case].self, from: data)
        else { return [] }
        return cases
    }()
}

@Suite struct ModerationTests {
    @Test func theFixtureCasesWereFound() {
        #expect(ModerationFixture.cases.count >= 29)
        #expect(Set(ModerationFixture.cases.map(\.kind)) == ["handle", "name"])
    }

    @Test(arguments: ModerationFixture.cases)
    func everyFixtureCasePasses(_ example: ModerationFixture.Case) throws {
        let kind = try #require(Moderation.Kind(rawValue: example.kind))
        let expected = try #require(Moderation.Verdict(rawValue: example.expected))
        #expect(Moderation.check(example.input, as: kind) == expected)
    }

    @Test func theCompiledWordsMatchTheFixture() throws {
        let words = try ModerationFixture.words()
        #expect(words.version == ModerationWords.version)
        #expect(Set(words.anywhere) == Set(ModerationWords.anywhere))
        #expect(Set(words.token) == ModerationWords.token)
        #expect(Set(words.reserved) == ModerationWords.reserved)

        var leet: [String: String] = [:]
        for (key, value) in ModerationWords.leet {
            leet[String(key)] = String(value)
        }
        #expect(leet == words.leet)
    }

    @Test func normalisingSwapsLeetAndSplitsOnEverythingElse() {
        let (tokens, compact) = Moderation.normalise("sh1t_happens")
        #expect(tokens == ["shit", "happens"])
        #expect(compact == "shithappens")
        #expect(Moderation.normalise("big.ass").tokens == ["big", "ass"])
        #expect(Moderation.normalise("🦊 fox").tokens == ["fox"])
        #expect(Moderation.normalise("").compact == "")
    }

    @Test func namesAreTrimmedTheWayTheServerTrims() {
        #expect(Moderation.trimmed("  Noor \n") == "Noor")
        #expect(Moderation.trimmed("\u{FEFF}Ava\u{3000}") == "Ava")
        // JavaScript's trim() leaves U+0085 alone, and it's a control character: invalid.
        #expect(Moderation.trimmed("\u{85}Ava") == "\u{85}Ava")
        #expect(Moderation.checkName("\u{85}Ava") == .invalid)
        // Twelve code points, emoji included; a thirteenth is too many.
        #expect(Moderation.checkName(String(repeating: "🦊", count: 12)) == .ok)
        #expect(Moderation.checkName(String(repeating: "🦊", count: 13)) == .invalid)
        // Joiners in an emoji are format characters, not control characters.
        #expect(Moderation.checkName("👩‍💻") == .ok)
    }

    @Test func handleInputIsTidiedAsItsTyped() {
        #expect(Moderation.cleanHandleInput("@Ava") == "ava")
        #expect(Moderation.cleanHandleInput("@@ava smith ") == "avasmith")
        #expect(Moderation.cleanHandleInput("noor-k") == "noor-k")
    }
}
