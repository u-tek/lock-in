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

    @Test func paletteListsTheStatesInWireOrder() {
        let tokens = LKMemberTone.allCases.map { $0.token }
        #expect(tokens == LKPalette.memberStates)
    }

    @Test func statesAreDistinguishableForEveryone() {
        // OKLab distance: about 0.02 is just noticeable side by side. Typical vision gets six
        // times that. The deficiencies flatten a whole colour axis, so for them the bar is three
        // and a half times, carried mostly by lightness steps between the states.
        for scheme in appearances {
            for vision in LKColorVision.allCases {
                let minimum = vision == .typical ? 0.12 : 0.07
                for (a, b) in pairs(LKMemberTone.allCases) {
                    let d = perceivedDistance(a.token.value(in: scheme), b.token.value(in: scheme), for: vision)
                    #expect(d >= minimum, "\(a) and \(b), \(scheme), \(vision.rawValue): \(d)")
                }
            }
        }
    }

    @Test func statesReadOnTheLockScreenAndInTheIsland() {
        // The activity renders with lkNightAppearance(), so only the dark values ever reach it.
        for tone in LKMemberTone.allCases {
            for background in [LKPalette.liveActivityBackground, LKPalette.islandBackground] {
                let ratio = tone.token.contrastRatio(on: background, in: .dark)
                #expect(ratio >= 4.5, "\(tone) on \(background.name): \(ratio)")
            }
        }
    }

    @Test func statesReadInTheApp() {
        for scheme in appearances {
            for tone in LKMemberTone.allCases {
                for background in [LKPalette.background, LKPalette.surface] {
                    let ratio = tone.token.contrastRatio(on: background, in: scheme)
                    #expect(ratio >= 4.5, "\(tone) on \(background.name), \(scheme): \(ratio)")
                }
            }
        }
    }

    @Test func statesSurviveAlwaysOn() {
        // Always-On dims the whole panel. WCAG's 0.05 flare term is what makes dim colours sink
        // into black, so scaling luminance to 40 % is a rough stand-in for the dimmed Lock
        // Screen. Shapes and large text need 3:1.
        let dimming = 0.4
        let black = LKPalette.islandBackground.dark.relativeLuminance * dimming
        for tone in LKMemberTone.allCases {
            let dimmed = tone.token.dark.relativeLuminance * dimming
            let ratio = (dimmed + 0.05) / (black + 0.05)
            #expect(ratio >= 3, "\(tone): \(ratio)")
        }
    }

    @Test func leftIsTheOnlyGreyedState() {
        for scheme in appearances {
            for tone in LKMemberTone.allCases {
                let chroma = OKLab(tone.token.value(in: scheme)).chroma
                if tone == .left {
                    #expect(chroma < 0.03, "left, \(scheme): \(chroma)")
                } else {
                    #expect(chroma > 0.06, "\(tone), \(scheme): \(chroma)")
                }
            }
        }
    }

    @Test func pillsKeepTheirTextReadable() {
        for scheme in appearances {
            let ink = LKPalette.textPrimary.value(in: scheme)
            for tone in LKMemberTone.allCases {
                let tint = tone.token.value(in: scheme)
                for background in [LKPalette.background, LKPalette.surface] {
                    let fill = tint.composited(over: background.value(in: scheme), opacity: LKColor.tintedFillOpacity)
                    let text = ink.contrastRatio(with: fill)
                    let symbol = tint.contrastRatio(with: fill)
                    #expect(text >= 4.5, "\(tone) pill text on \(background.name), \(scheme): \(text)")
                    #expect(symbol >= 3, "\(tone) pill symbol on \(background.name), \(scheme): \(symbol)")
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

    @Test @MainActor func symbolsExist() {
        for tone in LKMemberTone.allCases {
            #expect(UIImage(systemName: tone.symbolName) != nil, "\(tone.symbolName)")
        }
    }
}
