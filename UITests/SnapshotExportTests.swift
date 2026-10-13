import XCTest

/// Exports PNGs of screens for design review. Not a regression test: it never compares images.
///
/// One launch covers every screen: the app shows the first shot, and after each capture the test
/// posts a Darwin notification and the app steps to the next one in place (`SnapshotMode` in the
/// app). If a screen crashes the app, it's noted and the app is relaunched with the shots that
/// are left.
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
        var remaining = shots[...]
        let app = XCUIApplication()

        while !remaining.isEmpty {
            app.launchArguments = ["-LKSnapshots", remaining.joined(separator: ",")]
            app.launch()
            // The first frame of the first screen.
            Thread.sleep(forTimeInterval: 2.5)

            var crashed = false
            var previous: String?
            for (offset, shot) in remaining.enumerated() {
                if let previous {
                    postNext()
                    // A change of appearance takes longer to settle than a change of screen.
                    Thread.sleep(forTimeInterval: appearance(of: shot) == appearance(of: previous) ? 1.8 : 2.5)
                }
                previous = shot
                guard app.state == .runningForeground else {
                    // This screen crashed the app: note it and carry on from the next one.
                    failures.append(shot)
                    remaining = remaining.dropFirst(offset + 1)
                    crashed = true
                    break
                }
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
