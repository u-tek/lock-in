import XCTest

/// Films the scripted squad session (`IslandDemo` in the app) in the simulator's real Dynamic
/// Island and on its Lock Screen, for `scripts/island-demo.sh`. Not a regression test: it checks
/// only that the activity started, and writes what it saw.
///
/// The app's script, from the moment its activity starts: you, Noor and Kai locked in ("+2"),
/// Mateo joins at 12 s ("+3"), Noor cheers you at 22 s, the cheer clears at 40 s.
///
/// Environment (from xcodebuild with a `TEST_RUNNER_` prefix): `LK_ISLAND_DIR`, where the PNGs
/// go. Without it the test is skipped, so a plain `xcodebuild test` never runs it.
final class IslandDemoTests: XCTestCase {
    private var outputDirectory: URL!
    private var started = Date()

    @MainActor
    func testFilmTheIsland() throws {
        guard let path = ProcessInfo.processInfo.environment["LK_ISLAND_DIR"], !path.isEmpty else {
            throw XCTSkip("Run by scripts/island-demo.sh")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments = ["-LKIslandDemo", "YES"]
        app.launch()
        let marker = app.descendants(matching: .any)["lk.island.started"]
        XCTAssertTrue(marker.waitForExistence(timeout: 60), "The demo's Live Activity didn't start")
        started = Date()

        wait(until: 2)
        save("1-app")

        // Home: the activity moves into the island.
        XCUIDevice.shared.press(.home)
        wait(until: 5)
        save("2-island")

        // Long-press the island to expand it.
        expandIsland()
        save("3-island-expanded")
        XCUIDevice.shared.press(.home)

        // Mateo has joined: "+3".
        wait(until: 15)
        save("4-island-joined")

        // Noor's cheer, expanded.
        wait(until: 24)
        expandIsland()
        save("5-island-cheer")
        XCUIDevice.shared.press(.home)

        // The Lock Screen: lock, then wake.
        wait(until: 28)
        if pressLock() {
            sleep(2)
            _ = pressLock()
            wait(until: 33)
            save("6-lock-screen")
        }

        // The cheer gone, the timers still running.
        wait(until: 44)
        save("7-lock-screen-later")
    }

    /// Waits until `seconds` after the activity started.
    private func wait(until seconds: TimeInterval) {
        let remaining = started.addingTimeInterval(seconds).timeIntervalSinceNow
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
    }

    @MainActor
    private func expandIsland() {
        // The island sits centred at the top of the screen, about 30 points down on a 16 Pro.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.034)).press(forDuration: 1.2)
        sleep(1)
    }

    /// The simulator's side button. XCUIDevice has no public lock button on iOS; tests that need
    /// one call this selector, so it's guarded rather than assumed.
    private func pressLock() -> Bool {
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else { return false }
        _ = XCUIDevice.shared.perform(selector)
        return true
    }

    @MainActor
    private func save(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Couldn't write \(url.path): \(error)")
        }
    }
}
