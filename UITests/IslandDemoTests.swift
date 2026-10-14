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
///
/// The script films only the demo: the test writes `ready` there when it starts, waits for the
/// script's `recording`, and writes `done` at the end.
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
        defer { signal("done") }
        signal("ready")
        waitForSignal("recording", atMost: 20)

        let app = XCUIApplication()
        app.launchArguments = ["-LKIslandDemo", "YES"]
        app.launch()
        let marker = app.descendants(matching: .any)["lk.island.started"]
        let failed = app.descendants(matching: .any)["lk.island.failed"]
        let deadline = Date().addingTimeInterval(60)
        while !marker.exists, !failed.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }
        if failed.exists {
            save("0-failed")
            XCTFail("The demo's Live Activity didn't start: \(failed.label)")
            return
        }
        guard marker.exists else {
            save("0-failed")
            XCTFail("The demo's Live Activity didn't start within a minute")
            return
        }
        started = Date()

        wait(until: 2)
        save("1-app")

        // Home: the activity moves into the island.
        XCUIDevice.shared.press(.home)
        wait(until: 6)
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

    /// A file the script waits for.
    private func signal(_ name: String) {
        FileManager.default.createFile(atPath: outputDirectory.appendingPathComponent(name).path, contents: Data())
    }

    private func waitForSignal(_ name: String, atMost seconds: TimeInterval) {
        let path = outputDirectory.appendingPathComponent(name).path
        let deadline = Date().addingTimeInterval(seconds)
        while !FileManager.default.fileExists(atPath: path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
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
