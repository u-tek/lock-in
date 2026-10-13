import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

@Suite struct MemberToneTests {
    @Test func rawValuesAreTheWireValues() {
        // SPEC.md §4.3: 0 focusing, 1 break, 2 paused, 3 done, 4 left, 5 slipped.
        let rawValues = LKMemberTone.allCases.map { $0.rawValue }
        #expect(rawValues == [0, 1, 2, 3, 4, 5])
        #expect(LKMemberTone(rawValue: 1) == LKMemberTone.onBreak)
        #expect(LKMemberTone(rawValue: 4) == LKMemberTone.left)
        #expect(LKMemberTone(rawValue: 6) == nil)
    }

    @Test func catalogueListsTheStatesInWireOrder() {
        let tokens = LKMemberTone.allCases.map { $0.token }
        #expect(tokens == LKColorCatalogue.memberStates)
    }

    @Test func statesWearTheSystemColoursInTheSystemDoc() {
        // design/SYSTEM.md's member-state table.
        for tone in LKMemberTone.allCases {
            let (name, system) = expectedColour(tone)
            #expect(tone.token.uiKitName == name, "\(tone)")
            for scheme in appearances {
                let drawn = tone.token.resolved(in: scheme)
                #expect(distance(drawn, resolve(system, in: scheme)) < 0.001, "\(tone), \(scheme)")
            }
        }
    }

    @Test func focusingWearsTheTint() {
        for scheme in appearances {
            #expect(LKMemberTone.focusing.token.hexString(in: scheme) == LKColorCatalogue.tint.hexString(in: scheme))
        }
    }

    @Test func sixStatesSixColoursInEitherAppearance() {
        // Pairwise, in light and again in dark: no two states may resolve to the same colour, or
        // to near neighbours. 0.15 is a comfortable margin under the closest system pair here
        // (about 0.4); a state that drifted onto another's colour would land near 0.
        for scheme in appearances {
            for (a, b) in pairs(LKMemberTone.allCases) {
                let d = distance(a.token.resolved(in: scheme), b.token.resolved(in: scheme))
                #expect(d > 0.15, "\(a) and \(b), \(scheme): \(d)")
            }
        }
    }

    @Test func leftIsTheOnlyGreyState() {
        // Grey means "not here any more", so nothing else may be grey.
        for scheme in appearances {
            for tone in LKMemberTone.allCases {
                let c = components(tone.token.resolved(in: scheme))
                let spread = max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue)
                if tone == .left {
                    #expect(spread < 0.05, "left, \(scheme): \(spread)")
                } else {
                    #expect(spread > 0.2, "\(tone), \(scheme): \(spread)")
                }
            }
        }
    }

    @Test func symbolsAndTitlesAreDistinct() {
        let symbols = LKMemberTone.allCases.map { $0.symbolName }
        let titles = LKMemberTone.allCases.map { $0.title }
        #expect(Set(symbols).count == symbols.count)
        #expect(Set(titles).count == titles.count)
    }

    @Test func symbolsFollowTheSystemDoc() {
        let symbols = LKMemberTone.allCases.map { $0.symbolName }
        #expect(symbols == ["lock.fill", "cup.and.saucer.fill", "pause.fill", "checkmark", "hand.wave.fill", "drop.fill"])
    }

    @Test @MainActor func symbolsExist() {
        for tone in LKMemberTone.allCases {
            #expect(UIImage(systemName: tone.symbolName) != nil, "\(tone.symbolName)")
        }
    }

    private func expectedColour(_ tone: LKMemberTone) -> (String, UIColor) {
        switch tone {
        case .focusing: ("systemIndigo", .systemIndigo)
        case .onBreak: ("systemTeal", .systemTeal)
        case .paused: ("systemOrange", .systemOrange)
        case .done: ("systemGreen", .systemGreen)
        case .left: ("systemGray", .systemGray)
        case .slipped: ("systemPink", .systemPink)
        }
    }
}
