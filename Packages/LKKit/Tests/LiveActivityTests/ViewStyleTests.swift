import CoreGraphics
import Foundation
import Model
import SwiftUI
import Testing
import UIKit
@testable import LiveActivity

// The Live Activity's look (design/SYSTEM.md, "Live Activity"). The snapshots show how it looks;
// these pin the rules a picture can't be trusted to keep: which type each countdown uses, when a
// countdown takes its state's colour, that members are drawn as Locklings at every size the
// presentations use, and that the island's views add no padding of their own (Apple's templates
// leave the margins to the system).

@Suite struct CountdownStyleTests {
    @Test func countdownsUseTheSystemTextStyles() {
        // Lock Screen and the expanded island: Title 2 semibold. Compact island: Body semibold.
        // Squadmates a step under yours.
        #expect(ActivityTimer.lockScreen.textStyle == .title2)
        #expect(ActivityTimer.lockScreen.weight == .semibold)
        #expect(ActivityTimer.expanded == ActivityTimer.lockScreen)
        #expect(ActivityTimer.island.textStyle == .body)
        #expect(ActivityTimer.island.weight == .semibold)
        #expect(ActivityTimer.squadmate.textStyle == .subheadline)
        #expect(ActivityTimer.squadmate.weight == .semibold)
        #expect(ActivityTimer.smartStack == ActivityTimer.lockScreen)
    }

    @Test func standByUsesLargeFixedSizes() {
        // The system scales StandBy up already, so its timers are fixed sizes, not text styles.
        let start = LiveActivitySamples.fixtureDate
        let short = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(25 * 60))
        for style in [ActivityTimer.standBySquad, ActivityTimer.standBySolo(for: short)] {
            #expect(style.textStyle == nil, "\(style)")
            #expect(style.weight == .semibold, "\(style)")
            #expect(style.pointSize >= 40, "\(style)")
        }
    }

    @Test func everyCountdownHasMonospacedDigits() {
        let start = LiveActivitySamples.fixtureDate
        let long = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(90 * 60))
        let styles = [
            ActivityTimer.lockScreen, ActivityTimer.island, ActivityTimer.expanded, ActivityTimer.squadmate,
            ActivityTimer.smartStack, ActivityTimer.standBySquad, ActivityTimer.standBySolo(for: long),
        ]
        for style in styles {
            #expect(style.hasMonospacedDigits, "\(style)")
        }
    }

    @Test func standBysHeroMakesWayForTheHoursDigit() {
        let start = LiveActivitySamples.fixtureDate
        let short = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(25 * 60))
        let long = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(90 * 60))
        let pausedShort = LiveActivityPresentation.Countdown.paused(
            start...start.addingTimeInterval(90 * 60),
            pausedAt: start.addingTimeInterval(60 * 60)
        )
        let hero = ActivityTimer.standBySolo(for: short)
        let smaller = ActivityTimer.standBySolo(for: long)
        #expect(hero.pointSize > smaller.pointSize)
        // Half an hour left of a long session: no hours digit, so the hero fits again.
        #expect(ActivityTimer.standBySolo(for: pausedShort) == hero)
        #expect(ActivityTimer.standBySolo(for: .text("Done")) == hero)
    }

    // These call `CountdownText.resolve` rather than reading `resolvedInk` off a view: outside a
    // view hierarchy `@Environment` gives its default, `.light`, so the instance property couldn't
    // show the dark appearance. `@MainActor` because a View's static members are main-actor
    // isolated.

    @Test @MainActor func wordsStepBackWhateverTheInk() {
        // A finished member's word is secondary in either appearance; a timer takes the ink asked
        // for: the state's colour for your own, primary for squadmates' (their Locklings show the
        // state). The one exception is the state's colour on the light Lock Screen, below.
        let start = LiveActivitySamples.fixtureDate
        let running = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(25 * 60))
        let paused = LiveActivityPresentation.Countdown.paused(
            start...start.addingTimeInterval(25 * 60),
            pausedAt: start.addingTimeInterval(60)
        )
        let word = LiveActivityPresentation.Countdown.text("Done")
        for scheme in [ColorScheme.light, .dark] {
            for ink in [CountdownText.Ink.tone, .primary, .secondary] {
                let expected: CountdownText.Ink = (ink == .tone && scheme == .light) ? .primary : ink
                for countdown in [running, paused] {
                    let resolved = CountdownText.resolve(ink, for: countdown, in: scheme)
                    #expect(resolved == expected, "\(countdown), \(ink), \(scheme)")
                }
                #expect(CountdownText.resolve(ink, for: word, in: scheme) == .secondary, "\(ink), \(scheme)")
            }
        }
    }

    @Test @MainActor func yourOwnTimeTakesYourStatesColourByDefault() {
        let start = LiveActivitySamples.fixtureDate
        let running = LiveActivityPresentation.Countdown.running(start...start.addingTimeInterval(25 * 60))
        let tone = LiveActivityPresentation.tone(for: .onBreak)
        let timer = CountdownText(countdown: running, tone: tone, style: ActivityTimer.lockScreen)
        #expect(timer.ink == .tone)
        // In the dark (the island, StandBy, Always-On, the Smart Stack, the dark Lock Screen) your
        // time is in your state's colour. On the light Lock Screen teal, orange and green are under
        // 3:1 as text, so it takes the primary style and the Lockling and bar carry the state.
        #expect(CountdownText.resolve(.tone, for: running, in: .dark) == .tone)
        #expect(CountdownText.resolve(.tone, for: running, in: .light) == .primary)
    }
}

/// Members are Locklings, drawn by the Creature module. These check the sizes the presentations
/// ask for and that every member draws, in and out of Always-On.
@Suite struct LocklingTests {
    /// One member in every state.
    private static let members = LiveActivitySamples.squadOfSix(now: LiveActivitySamples.fixtureDate)
        .presentation.members

    @Test func everyStateIsDrawn() {
        #expect(Set(Self.members.map(\.state)) == Set(MemberState.allCases))
    }

    @Test func sizesSuitTheirPresentations() {
        // The compact island is 36.67 tall and its limited-width form a 28-point circle (HIG).
        #expect(ActivityMetrics.islandCreature >= 20 && ActivityMetrics.islandCreature <= 28)
        #expect(ActivityMetrics.smartStackCreature <= 28)
        // Rows and the solo layouts are at or over the 28 points where a Lockling shows its hat
        // and what it's holding; under that it's only the lock and face.
        for size in [
            ActivityMetrics.expandedRowCreature, ActivityMetrics.lockScreenRowCreature, ActivityMetrics.expandedCreature,
            ActivityMetrics.soloCreature, ActivityMetrics.soloStandByCreature,
        ] {
            #expect(size >= 28, "\(size)")
        }
        // Six columns, 4 points apart, across an iPhone SE's Lock Screen card (343 points less
        // the margins).
        let row = 6 * ActivityMetrics.lockScreenRowCreature + 5 * 4
        #expect(row <= 343 - 2 * ActivityMetrics.lockScreenMargin)
    }

    /// Drawn, every member at every size, in and out of Always-On: a square of the asked size with
    /// a Lockling in it, and in Always-On an outline that lights far fewer pixels.
    @Test(arguments: ActivityMetrics.creatureSizes)
    @MainActor func everyMemberDrawsAsALockling(size: CGFloat) throws {
        for member in Self.members {
            let normal = try Self.inked(MemberBadge(member, size: size), size: size)
            let alwaysOn = try Self.inked(
                MemberBadge(member, size: size).environment(\.isLuminanceReduced, true),
                size: size
            )
            #expect(normal > 0.1, "\(member.name) at \(size)")
            #expect(alwaysOn > 0.02, "\(member.name) at \(size), Always-On")
            #expect(alwaysOn < normal * 0.8, "\(member.name) at \(size): Always-On should be an outline")
        }
    }

    /// The share of pixels with any opacity, drawn at 3x on a clear background. Checks the image is
    /// the square asked for.
    @MainActor
    private static func inked(_ view: some View, size: CGFloat) throws -> Double {
        let scale: CGFloat = 3
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        #expect(width == Int((size * scale).rounded()) && height == width, "\(size): \(width) × \(height)")
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "Couldn't read the drawn Lockling")
        var inked = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 0 {
            inked += 1
        }
        return Double(inked) / Double(width * height)
    }
}

/// Apple's island templates leave the margins to the system and keep compact content snug
/// against the camera. Measured here, every sample: the views are exactly as big as what they
/// draw, with no padding of our own.
@Suite struct IslandLayoutTests {
    /// The compact island's height (HIG, iOS dimensions).
    private static let islandHeight: CGFloat = 36.67

    @Test(arguments: LiveActivitySamples.catalogue(now: LiveActivitySamples.fixtureDate))
    @MainActor func compactLeadingAndMinimalAreTheLocklingAlone(sample: LiveActivitySample) {
        let side = ActivityMetrics.islandCreature
        let leading = Self.size(of: CompactLeadingView(attributes: sample.attributes, state: sample.state))
        let minimal = Self.size(of: MinimalView(attributes: sample.attributes, state: sample.state))
        #expect(leading == CGSize(width: side, height: side), "\(sample.id): \(leading)")
        #expect(minimal == CGSize(width: side, height: side), "\(sample.id): \(minimal)")
    }

    @Test(arguments: LiveActivitySamples.catalogue(now: LiveActivitySamples.fixtureDate))
    @MainActor func compactTrailingIsOnlyAsWideAsItsLongestReading(sample: LiveActivitySample) {
        let presentation = sample.presentation
        let size = Self.size(of: CompactTrailingView(attributes: sample.attributes, state: sample.state))
        #expect(size.height <= Self.islandHeight, "\(sample.id): \(size)")
        switch presentation.compactTrailing {
        case .countdown(let countdown, _):
            if let reserved = countdown.reservedWidth(fontSize: ActivityTimer.island.pointSize) {
                #expect(size.width == reserved, "\(sample.id): \(size.width) for \(reserved)")
            } else {
                // A word ("Done") takes its own width, and no more than a timer would.
                #expect(size.width > 0 && size.width <= ActivityTimer.island.pointSize * 4, "\(sample.id): \(size)")
            }
        case .squadmates:
            #expect(size.width > 0 && size.width <= ActivityTimer.island.pointSize * 2, "\(sample.id): \(size)")
        case .cheer:
            // One symbol, about as wide as "+3".
            #expect(size.width > 0 && size.width <= ActivityTimer.island.pointSize * 2, "\(sample.id): \(size)")
        case .empty:
            #expect(size.width == 0, "\(sample.id): \(size)")
        }
    }

    @Test(arguments: LiveActivitySamples.catalogue(now: LiveActivitySamples.fixtureDate))
    @MainActor func expandedFitsInsideTheIsland(sample: LiveActivitySample) {
        let width: CGFloat = 371
        let leading = Self.size(of: ExpandedLeadingView(attributes: sample.attributes, state: sample.state))
        let trailing = Self.size(of: ExpandedTrailingView(attributes: sample.attributes, state: sample.state))
        let bottom = Self.size(of: ExpandedBottomView(attributes: sample.attributes, state: sample.state), width: width)
        let side = ActivityMetrics.expandedCreature
        #expect(leading == CGSize(width: side, height: side), "\(sample.id): \(leading)")
        // The time sits at the top of a box as tall as the Lockling, so their tops line up.
        #expect(trailing.height == side, "\(sample.id): \(trailing)")
        // The expanded island is at most 160 tall. Above the bottom region: the system's top
        // margin and the Lockling; below it, the bottom margin. Leave 40 for the margins.
        #expect(side + bottom.height + 40 <= 160, "\(sample.id): bottom \(bottom.height)")
    }

    @Test @MainActor func soloShowsButtonsOnlyWhileThereIsATimer() {
        let now = LiveActivitySamples.fixtureDate
        for state in MemberState.allCases {
            let sample = LiveActivitySamples.solo(now: now, me: state)
            let bottom = Self.size(of: ExpandedBottomView(attributes: sample.attributes, state: sample.state), width: 371)
            switch sample.presentation.sessionControls {
            case .pauseAndEnd, .resumeAndEnd:
                #expect(bottom.height >= 28, "\(state): \(bottom)")
            case .hidden:
                // Nothing drawn: the island shrinks to fit rather than keep an empty row.
                #expect(bottom.height == 0, "\(state): \(bottom)")
            }
        }
    }

    @MainActor
    private static func size(of view: some View, width: CGFloat? = nil) -> CGSize {
        let proposal = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let fitted = UIHostingController(rootView: view.fixedSize(horizontal: width == nil, vertical: true))
            .sizeThatFits(in: proposal)
        // Rounded to the pixel at 3x, so layout's float noise doesn't fail an equality.
        return CGSize(width: (fitted.width * 3).rounded() / 3, height: (fitted.height * 3).rounded() / 3)
    }
}
