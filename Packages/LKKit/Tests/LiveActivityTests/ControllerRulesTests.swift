#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
import Foundation
import Model
import Testing
@testable import LiveActivity

// The controller itself needs a running app to start activities, so these test what it's built
// from: token formatting, the update rules and the error mapping. No `Activity` is created.

@Suite struct PushTokenTests {
    @Test func lowercaseHexTwoDigitsPerByte() {
        #expect(PushToken.hex(Data([0x00, 0x0F, 0xA0, 0xFF])) == "000fa0ff")
        #expect(PushToken.hex(Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])) == "0123456789abcdef")
    }

    @Test func emptyDataIsAnEmptyString() {
        #expect(PushToken.hex(Data()) == "")
    }

    @Test func everyByteValue() {
        let bytes = Data((0...255).map { UInt8($0) })
        let expected = (0...255).map { String(format: "%02x", $0) }.joined()
        #expect(PushToken.hex(bytes) == expected)
    }

    @Test func apnsSizedToken() {
        // Activity push tokens have been 32 bytes in practice; nothing here depends on it.
        var generator = SystemRandomNumberGenerator()
        let token = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let hex = PushToken.hex(token)
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func notTheDescription() {
        // `Data.description` gives "4 bytes", which is what a careless upload would send.
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(PushToken.hex(data) == "deadbeef")
        #expect(PushToken.hex(data) != data.description)
    }
}

@Suite struct ContentPolicyTests {
    private func state(_ version: Int) -> LockinAttributes.ContentState {
        LiveActivitySamples.squadOfSix(now: LiveActivitySamples.fixtureDate).state.withVersion(version)
    }

    @Test func newerAndEqualVersionsGoThrough() {
        #expect(ContentPolicy.accepts(state(43), over: state(42)))
        #expect(ContentPolicy.accepts(state(42), over: state(42)))
    }

    @Test func olderVersionsNeverRollTheViewBack() {
        #expect(!ContentPolicy.accepts(state(41), over: state(42)))
        #expect(!ContentPolicy.accepts(state(0), over: state(Int(Int32.max))))
    }

    @Test func endedActivitiesLeaveThirtyMinutesLater() {
        let now = LiveActivitySamples.fixtureDate
        #expect(ContentPolicy.dismissalDate(endingAt: now) == now.addingTimeInterval(1_800))
        #expect(ContentPolicy.dismissalDate(endingAt: now).timeIntervalSince(now) == LiveActivityLimits.dismissalAfterEndSeconds)
    }

    @Test func squadSessionsOutrankSolo() {
        let squad = LiveActivitySamples.squadOfSix().attributes
        let solo = LiveActivitySamples.solo().attributes
        #expect(ContentPolicy.relevanceScore(for: squad) > ContentPolicy.relevanceScore(for: solo))
    }
}

@Suite struct LiveActivityErrorTests {
    @Test func everyCaseExplainsItself() {
        let cases: [LiveActivityError] = [.disabled, .unsupported, .notInForeground, .tooMany, .tooLarge, .failed("boom")]
        let descriptions = cases.map(\.description)
        #expect(Set(descriptions).count == cases.count)
        #expect(cases.allSatisfy { $0.errorDescription == $0.description })
        #expect(LiveActivityError.failed("boom").description.hasSuffix("boom"))
    }

    #if canImport(ActivityKit) && os(iOS)
    @Test func systemRefusalsMapToWhatTheAppCanSay() {
        #expect(LiveActivityError(ActivityAuthorizationError.denied) == .disabled)
        #expect(LiveActivityError(ActivityAuthorizationError.unsupported) == .unsupported)
        #expect(LiveActivityError(ActivityAuthorizationError.unentitled) == .unsupported)
        #expect(LiveActivityError(ActivityAuthorizationError.visibility) == .notInForeground)
        #expect(LiveActivityError(ActivityAuthorizationError.globalMaximumExceeded) == .tooMany)
        #expect(LiveActivityError(ActivityAuthorizationError.targetMaximumExceeded) == .tooMany)
        #expect(LiveActivityError(ActivityAuthorizationError.attributesTooLarge) == .tooLarge)
    }

    @Test func ourOwnErrorsPassThrough() {
        #expect(LiveActivityError(LiveActivityError.tooLarge) == .tooLarge)
        #expect(LiveActivityError(LiveActivityError.failed("x")) == .failed("x"))
    }

    @Test func anythingElseIsAFailure() {
        let error = NSError(domain: "test", code: 7)
        guard case .failed(let reason) = LiveActivityError(error) else {
            Issue.record("An unknown error should map to .failed")
            return
        }
        #expect(reason.contains("test"))
    }
    #endif
}

private extension LockinAttributes.ContentState {
    func withVersion(_ version: Int) -> LockinAttributes.ContentState {
        var copy = self
        copy.v = version
        return copy
    }
}
