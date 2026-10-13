import XCTest

/// Exports PNGs of screens for design review. Not a regression test: it never compares images.
///
/// One launch covers every screen: the app shows the first shot, and after each capture the test
/// posts a Darwin notification and the app steps to the next one in place (`SnapshotMode` in the
/// app). Before each capture the test waits for the app's marker for that shot
/// (`lk.snapshot.<index>`), so a slow screen is never photographed as the one before it; a shot
/// whose marker never appears counts as not rendered. If a screen crashes the app, it's noted and
/// the app is relaunched with the shots that are left. How long each shot took to appear goes to
/// `timings.txt` beside the renders.
///
/// Environment (pass from xcodebuild with a `TEST_RUNNER_` prefix, as
/// `scripts/export-snapshots.sh` does):
/// - `LK_SNAPSHOT_ROUTES`: comma-separated routes (see `SnapshotGallery` in the app).
/// - `LK_SNAPSHOT_APPEARANCES`: comma-separated, `light` and/or `dark`. Default `light,dark`.
/// - `LK_SNAPSHOT_DIR`: directory to write `<route>-<appearance>.png` into. Without it (a run
///   from Xcode), the screenshots are attached to the test report instead.
final class SnapshotExportTests: XCTestCase {
    private static let nextNotification = "com.lockin.snapshot.next"

    @MainActor
    func testExportSnapshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let routes = list(environment["LK_SNAPSHOT_ROUTES"], default: ["home"])
        let appearances = list(environment["LK_SNAPSHOT_APPEARANCES"], default: ["light", "dark"])
        let outputDirectory = environment["LK_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        // Every light screen, then every dark one: the appearance switches once, not every shot.
        let shots = appearances.flatMap { appearance in routes.map { "\($0)@\(appearance)" } }
        var failures: [String] = []
        var timings: [String] = []
        var remaining = shots[...]
        let app = XCUIApplication()

        while !remaining.isEmpty {
            app.launchArguments = ["-LKSnapshots", remaining.joined(separator: ",")]
            app.launch()

            var crashed = false
            var previous: String?
            for (offset, shot) in remaining.enumerated() {
                if previous != nil {
                    postNext()
                }
                // The app numbers shots from 0 in each launch, as this loop does.
                let asked = Date()
                let shown = app.descendants(matching: .any)["lk.snapshot.\(offset)"].waitForExistence(timeout: 30)
                timings.append(String(format: "%@ %@ after %.1f s", shot, shown ? "shown" : "NOT shown", Date().timeIntervalSince(asked)))
                // Then let it settle: the first screen and a change of appearance take longest.
                let settle = previous == nil ? 1.5 : (appearance(of: shot) == appearance(of: previous!) ? 1.0 : 2.0)
                previous = shot
                guard app.state == .runningForeground else {
                    // This screen crashed the app: note it and carry on from the next one.
                    failures.append(shot)
                    remaining = remaining.dropFirst(offset + 1)
                    crashed = true
                    break
                }
                guard shown else {
                    // Still showing an earlier screen: capturing now would file it under this name.
                    failures.append(shot)
                    continue
                }
                Thread.sleep(forTimeInterval: settle)
                let name = shot.replacingOccurrences(of: "@", with: "-")
                clearSystemBanners()
                let screenshot = XCUIScreen.main.screenshot()
                if let outputDirectory {
                    // Atomic, so a phone cut short never leaves half a PNG behind.
                    try screenshot.pngRepresentation.write(to: outputDirectory.appendingPathComponent("\(name).png"), options: .atomic)
                } else {
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            if !crashed {
                remaining = []
            }
            app.terminate()
        }

        if let outputDirectory {
            try timings.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
        }
        if let outputDirectory, !failures.isEmpty {
            try failures.joined(separator: "\n").write(to: outputDirectory.appendingPathComponent("failures.txt"), atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(failures.isEmpty, "These screens didn't render: \(failures.joined(separator: ", "))")
    }

    private func postNext() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.nextNotification as CFString),
            nil,
            nil,
            true
        )
    }

    /// A fresh simulator posts notifications of its own (like "Ready for Apple Intelligence"):
    /// swipe away any banner before it can cover a screen.
    private func clearSystemBanners() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'NotificationShortLookView' OR label BEGINSWITH 'Ready for Apple Intelligence'"))
            .firstMatch
        guard banner.exists else { return }
        banner.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func appearance(of shot: String) -> Substring {
        shot.split(separator: "@").last ?? ""
    }

    private func list(_ value: String?, default fallback: [String]) -> [String] {
        let items = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return items.isEmpty ? fallback : items
    }
}
