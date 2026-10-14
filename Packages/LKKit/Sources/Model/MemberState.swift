import Foundation

/// What a squad member is doing, as carried in `Member.s`. Each state has its own creature pose
/// (SPEC.md §1.3).
public enum MemberState: Int, Codable, CaseIterable, Sendable {
    case focusing = 0
    case onBreak = 1
    case paused = 2
    case done = 3
    /// Ended early.
    case left = 4
    /// Opened a shielded app during Deep Focus (M8): shown for 5 minutes while the timer keeps
    /// running, then back to focusing (docs/decisions/0009).
    case slipped = 5

    /// Still in the session, with a timer that is running or will run again: counts towards
    /// keeping the activity fresh. A slip doesn't stop the timer, so slipped is active.
    public var isActive: Bool {
        switch self {
        case .focusing, .onBreak, .paused, .slipped: true
        case .done, .left: false
        }
    }
}
