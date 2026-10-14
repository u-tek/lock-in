import Testing
@testable import Model

/// The cheers (`Cheer.k`): the app's cheer picker lists `CheerKind.allCases`, and the Live
/// Activity draws the one sent to you, so both show the same eight in the same order.
@Suite struct CheerKindTests {
    @Test func theCheerPickerListsEightKindsInWireOrder() {
        // The server takes 0–7 (`MAX_CHEER_KIND`), and the order is the wire format.
        #expect(CheerKind.allCases.count == 8)
        #expect(CheerKind.allCases.map(\.rawValue) == Array(0...7))
        #expect(CheerKind.allCases.map(\.id) == Array(0...7))
        #expect(CheerKind.allCases == [.applause, .fire, .star, .heart, .lightning, .thumbsUp, .party, .sparkles])
    }

    @Test(arguments: [8, 11, 42, -1, Int.max, Int.min])
    func unknownKindsAreSparkles(raw: Int) {
        #expect(CheerKind(kind: raw) == .sparkles)
        let cheer = LockinAttributes.ContentState.Cheer(f: "ava", t: "me", k: raw, at: 1_791_900_650)
        #expect(cheer.kind == .sparkles)
    }

    @Test func knownKindsAreThemselves() {
        for kind in CheerKind.allCases {
            #expect(CheerKind(kind: kind.rawValue) == kind)
            let cheer = LockinAttributes.ContentState.Cheer(f: "ava", t: "me", k: kind.rawValue, at: 1_791_900_650)
            #expect(cheer.kind == kind)
        }
    }

    @Test func everyKindHasItsOwnSymbolAndWord() {
        let symbols = CheerKind.allCases.map(\.symbolName)
        let titles = CheerKind.allCases.map(\.title)
        #expect(Set(symbols).count == symbols.count)
        #expect(Set(titles).count == titles.count)
        #expect(titles == ["Applause", "Fire", "Star", "Heart", "Lightning", "Thumbs up", "Party", "Sparkles"])
    }

    @Test func alwaysOnSymbolsAreTheOutlines() {
        // Nothing glows in Always-On: the same symbol without its fill.
        for kind in CheerKind.allCases {
            #expect(!kind.outlineSymbolName.hasSuffix(".fill"), "\(kind)")
            let filled = kind.symbolName.hasSuffix(".fill") ? String(kind.symbolName.dropLast(5)) : kind.symbolName
            #expect(kind.outlineSymbolName == filled, "\(kind)")
        }
    }

    @Test func theSquadSixFixtureCheerIsAHeart() throws {
        let state = try Fixture.contentState("squad-6")
        let cheer = try #require(state.c)
        #expect(cheer.kind == .heart)
    }
}
