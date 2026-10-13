import Foundation
import Model

/// The rules for what goes into each `ActivityContent`, kept apart from ActivityKit so the tests
/// can check them without starting an activity.
enum ContentPolicy {
    /// Whether `state` may replace `current` on screen.
    ///
    /// The server's version only goes up, and the app also updates the activity locally (Apple
    /// recommends both, because pushes can be missed: SPEC.md §4.4). A local update built from an
    /// older snapshot must not undo a newer push that arrived first. An equal version is let
    /// through: it's the same state again, or a solo session the app versions itself.
    static func accepts(_ state: LockinAttributes.ContentState, over current: LockinAttributes.ContentState) -> Bool {
        state.v >= current.v
    }

    /// When an ended activity leaves the Lock Screen: 30 minutes after the end (SPEC.md §4.4), the
    /// same `dismissal-date` the server sends with its `end` push.
    static func dismissalDate(endingAt now: Date) -> Date {
        now.addingTimeInterval(LiveActivityLimits.dismissalAfterEndSeconds)
    }

    /// Which activity takes the Dynamic Island if more than one is running. Orphans are ended on
    /// launch, so normally there's only one; if a solo one survives alongside a squad session,
    /// the squad wins.
    static func relevanceScore(for attributes: LockinAttributes) -> Double {
        attributes.isSolo ? 50 : 100
    }
}
