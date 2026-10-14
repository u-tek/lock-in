import AppIntents
import Testing
@testable import LiveActivity

/// The Live Activity's buttons run their intents in the app's process, which hands each command
/// to the session engine through `SessionIntentBridge`. Serialised: the bridge is shared.
@Suite(.serialized) @MainActor struct SessionIntentTests {
    /// Collects what the handler receives. Main-actor isolated, so the handler can hand it
    /// commands without sharing mutable state across actors.
    @MainActor final class Recorder {
        var commands: [SessionIntentBridge.Command] = []

        func record(_ command: SessionIntentBridge.Command) {
            commands.append(command)
        }
    }

    @Test func eachButtonSendsItsCommand() async throws {
        let recorder = Recorder()
        SessionIntentBridge.shared.handler = { command in
            await recorder.record(command)
        }
        defer { SessionIntentBridge.shared.handler = nil }

        _ = try await PauseSessionIntent().perform()
        #expect(recorder.commands == [.pause])
        _ = try await ResumeSessionIntent().perform()
        #expect(recorder.commands == [.pause, .resume])
        _ = try await EndSessionIntent().perform()
        #expect(recorder.commands == [.pause, .resume, .end])
    }

    /// The intent waits for the handler, so the activity has its update before the system is told
    /// the intent finished.
    @Test func theIntentWaitsForTheHandlerToFinish() async throws {
        let recorder = Recorder()
        SessionIntentBridge.shared.handler = { command in
            // A hop off the main actor and back, as the engine's activity update makes.
            await Task.detached { await Task.yield() }.value
            await recorder.record(command)
        }
        defer { SessionIntentBridge.shared.handler = nil }

        _ = try await EndSessionIntent().perform()
        #expect(recorder.commands == [.end])
    }

    /// Before the app has set a handler (or in the widget extension, which never does), a press is
    /// dropped quietly: no throw, no trap, nothing kept to replay later.
    @Test func withoutAHandlerNothingHappens() async throws {
        SessionIntentBridge.shared.handler = nil
        _ = try await PauseSessionIntent().perform()
        _ = try await ResumeSessionIntent().perform()
        _ = try await EndSessionIntent().perform()

        // Setting a handler afterwards replays nothing.
        let recorder = Recorder()
        SessionIntentBridge.shared.handler = { command in
            await recorder.record(command)
        }
        defer { SessionIntentBridge.shared.handler = nil }
        for _ in 0..<5 {
            await Task.yield()
        }
        #expect(recorder.commands.isEmpty)
    }

    /// Only the Live Activity shows these: outside a session there's nothing to pause, so they stay
    /// out of Shortcuts, Spotlight and Siri.
    @Test func theyStayOutOfShortcuts() {
        #expect(!PauseSessionIntent.isDiscoverable)
        #expect(!ResumeSessionIntent.isDiscoverable)
        #expect(!EndSessionIntent.isDiscoverable)
    }
}
