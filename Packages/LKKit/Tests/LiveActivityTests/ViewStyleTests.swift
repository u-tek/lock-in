import CoreGraphics
import Foundation
import Model
import SwiftUI
import Testing
import UIKit
@testable import LiveActivity

// The Live Activity's look (design/SYSTEM.md, "Live Activity"). The snapshots show how it looks;
// these pin the rules a picture can't be trusted to keep: which type each countdown uses, when a
// countdown takes its state's colour, and how the monogram's status badge sits and is cut out, at
// every size the presentations draw.

@Suite struct CountdownStyleTests {
    @Test func countdownsUseTheSystemTextStyles() {
        // Lock Screen: Title 2 semibold. Island: Body semibold. Squadmates a step under yours.
        #expect(ActivityTimer.lockScreen.textStyle == .title2)
        #expect(ActivityTimer.lockScreen.weight == .semibold)
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
            ActivityTimer.lockScreen, ActivityTimer.island, ActivityTimer.squadmate, ActivityTimer.smartStack,
            ActivityTimer.standBySquad, ActivityTimer.standBySolo(for: long),
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
        // for: the state's colour for your own, primary for squadmates' (their monograms carry the
        // colour). The one exception is the state's colour on the light Lock Screen, below.
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
        // 3:1 as text, so it takes the primary style and the monogram and bar carry the colour.
        #expect(CountdownText.resolve(.tone, for: running, in: .dark) == .tone)
        #expect(CountdownText.resolve(.tone, for: running, in: .light) == .primary)
    }
}

@Suite struct MemberBadgeTests {
    /// One member in every state.
    private static let members = LiveActivitySamples.squadOfSix(now: LiveActivitySamples.fixtureDate)
        .presentation.members

    @Test func everyStateIsDrawn() {
        #expect(Set(Self.members.map(\.state)) == Set(MemberState.allCases))
    }

    @Test func smallMonogramsShowTheStateSymbolInsteadOfABadge() {
        let small = [ActivityMetrics.islandBadge, ActivityMetrics.expandedChipBadge, ActivityMetrics.smartStackBadge]
        for size in small {
            #expect(!MemberBadgeGeometry(size: size).showsStatusBadge, "\(size)")
        }
        let badged = [
            ActivityMetrics.lockScreenRowBadge, ActivityMetrics.soloBadge, ActivityMetrics.soloStandByBadge,
            ActivityMetrics.expandedBadge,
        ]
        for size in badged {
            #expect(MemberBadgeGeometry(size: size).showsStatusBadge, "\(size)")
        }
        #expect(Set(small + badged) == Set(ActivityMetrics.badgeSizes))
        #expect(MemberBadge.symbolOnlyBelow == MemberBadgeGeometry.symbolOnlyBelow)
    }

    @Test(arguments: ActivityMetrics.badgeSizes)
    func statusBadgeSitsInTheCornerInsideTheFrame(size: CGFloat) {
        let geometry = MemberBadgeGeometry(size: size)
        guard geometry.showsStatusBadge else { return }
        // Inside the frame, in its bottom-trailing corner: the size the layout measures is the
        // size drawn, and a neighbour in the row never runs into it.
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        #expect(frame.contains(geometry.statusFrame), "\(size)")
        #expect(geometry.statusFrame.maxX == size && geometry.statusFrame.maxY == size, "\(size)")
        // Attached to the circle: its centre inside it and its edge past it, like Contacts'.
        let centre = CGPoint(x: geometry.statusFrame.midX, y: geometry.statusFrame.midY)
        let distance = hypot(centre.x - size / 2, centre.y - size / 2)
        #expect(distance < size / 2, "\(size)")
        #expect(distance + geometry.statusDiameter / 2 > size / 2, "\(size)")
    }

    @Test(arguments: ActivityMetrics.badgeSizes)
    func statusBadgeIsBigEnoughToRead(size: CGFloat) {
        let geometry = MemberBadgeGeometry(size: size)
        guard geometry.showsStatusBadge else { return }
        #expect(geometry.statusDiameter >= 12, "\(size)")
        #expect(geometry.symbolSize >= 6.5, "\(size)")
    }

    @Test(arguments: ActivityMetrics.badgeSizes)
    func notchIsTheBadgeWithAGapAllRound(size: CGFloat) {
        let geometry = MemberBadgeGeometry(size: size)
        #expect(geometry.gap >= 1.5, "\(size)")
        // On the half point, so it lands on whole pixels at 2x and 3x alike.
        #expect((geometry.gap * 2).rounded() == geometry.gap * 2, "\(size)")
        #expect(geometry.notch.insetBy(dx: geometry.gap, dy: geometry.gap) == geometry.statusFrame, "\(size)")
    }

    /// Drawn, with every member and in and out of Always-On: the gap round the status badge is
    /// clear, whatever the initial, so the badge reads on any background; outside Always-On the
    /// circle and the badge are solid, and in it the circle is only an outline.
    @Test(arguments: ActivityMetrics.badgeSizes)
    @MainActor func gapIsClearAndAlwaysOnFillsNothing(size: CGFloat) throws {
        let geometry = MemberBadgeGeometry(size: size)
        guard geometry.showsStatusBadge else { return }
        let badgeCentre = CGPoint(x: geometry.statusFrame.midX, y: geometry.statusFrame.midY)
        // Halfway across the gap, on the diagonal towards the monogram's centre: inside the
        // circle, so only the notch can make it clear.
        let reach = (geometry.statusDiameter / 2 + geometry.gap / 2) / CGFloat(2).squareRoot()
        let gap = CGPoint(x: badgeCentre.x - reach, y: badgeCentre.y - reach)
        // On the circle, between its edge and the initial.
        let body = CGPoint(x: size * 0.2, y: size / 2)

        for member in Self.members {
            for isLuminanceReduced in [false, true] {
                let badge = MemberBadge(member, size: size)
                    .environment(\.isLuminanceReduced, isLuminanceReduced)
                let alpha = try Self.alphas(at: [gap, body, badgeCentre], of: badge)
                let label = "\(member.name) at \(size), Always-On \(isLuminanceReduced)"
                #expect(alpha[0] < 32, "\(label): gap \(alpha[0])")
                if isLuminanceReduced {
                    #expect(alpha[1] < 32, "\(label): circle filled \(alpha[1])")
                } else {
                    #expect(alpha[1] > 223, "\(label): circle \(alpha[1])")
                    #expect(alpha[2] > 223, "\(label): badge \(alpha[2])")
                }
            }
        }
    }

    /// Opacity, 0 to 255, at each point (in points) of the view drawn at 3x on a clear background.
    @MainActor
    private static func alphas(at points: [CGPoint], of view: some View) throws -> [UInt8] {
        let scale: CGFloat = 3
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        // Redrawn into a bitmap of known layout, rows from the top, so the bytes can be read.
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
        try #require(drawn, "Couldn't read the drawn badge")
        return points.map { point in
            let x = min(max(Int(point.x * scale), 0), width - 1)
            let y = min(max(Int(point.y * scale), 0), height - 1)
            return pixels[(y * width + x) * 4 + 3]
        }
    }
}
