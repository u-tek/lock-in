import Testing
@testable import DesignSystem

@Suite struct RGBTests {
    @Test func hexRoundTrips() {
        let values: [UInt32] = [0x000000, 0xFFFFFF, 0xFFB23F, 0x0D0B17, 0x123456]
        for value in values {
            #expect(RGB(hex: value).hex == value)
        }
        #expect(RGB(hex: 0xFFB23F).hexString == "#FFB23F")
        #expect(RGB(hex: 0x0D0B17).hexString == "#0D0B17")
    }

    @Test func contrastRatioMatchesWCAG() {
        let white = RGB(hex: 0xFFFFFF), black = RGB(hex: 0x000000)
        #expect(abs(black.relativeLuminance) < 1e-9)
        #expect(abs(white.relativeLuminance - 1) < 1e-9)
        #expect(abs(white.contrastRatio(with: black) - 21) < 1e-9)
        #expect(abs(white.contrastRatio(with: white) - 1) < 1e-9)

        // #777777 on white is the textbook grey that just misses 4.5:1.
        let grey = RGB(hex: 0x777777)
        let ratio = grey.contrastRatio(with: white)
        #expect(abs(ratio - 4.478) < 0.005)
        #expect(ratio == white.contrastRatio(with: grey))
    }

    @Test func compositingBlendsTowardsTheBackground() {
        let red = RGB(hex: 0xFF0000), blue = RGB(hex: 0x0000FF)
        #expect(red.composited(over: blue, opacity: 0.5) == RGB(red: 0.5, green: 0, blue: 0.5))
        #expect(red.composited(over: blue, opacity: 1) == red)
        #expect(red.composited(over: blue, opacity: 0) == blue)
        // Out-of-range opacities are clamped rather than extrapolated.
        #expect(red.composited(over: blue, opacity: 2) == red)
    }

    @Test func simulationLeavesWhiteAndBlackAlone() {
        let white = RGB(hex: 0xFFFFFF), black = RGB(hex: 0x000000)
        for vision in LKColorVision.allCases {
            #expect(white.simulating(vision).distance(to: white) < 0.005, "\(vision.rawValue)")
            #expect(black.simulating(vision).distance(to: black) < 0.005, "\(vision.rawValue)")
        }
    }

    @Test func simulationCollapsesRedAndGreenForDeuteranopia() {
        // The state-colour checks are only worth something if the simulation really flattens
        // red–green differences.
        let red = RGB(hex: 0xFF0000), green = RGB(hex: 0x00A000)
        #expect(red.distance(to: green) > 0.3)
        #expect(perceivedDistance(red, green, for: .deuteranopia) < 0.08)
        #expect(red.simulating(.typical) == red)
    }

    @Test func greysHaveNoChroma() {
        #expect(OKLab(RGB(hex: 0x808080)).chroma < 0.001)
        #expect(OKLab(RGB(hex: 0xFFB23F)).chroma > 0.1)
    }
}
