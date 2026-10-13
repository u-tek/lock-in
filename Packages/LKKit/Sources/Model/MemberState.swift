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
    /// Opened a shielded app during Deep Focus (M8).
    case slipped = 5

    /// Still in the session, with a timer that will run again: counts towards keeping the
    /// activity fresh.
    public var isActive: Bool {
        switch self {
        case .focusing, .onBreak, .paused: true
        case .done, .left, .slipped: false
        }
    }
}
