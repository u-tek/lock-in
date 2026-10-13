import Foundation

/// How long a session runs (SPEC.md §1.4): 25, 50 or 90 minutes, or a custom length with Plus.
public enum SessionPreset: Hashable, Sendable, Identifiable {
    case twentyFive
    case fifty
    case ninety
    /// Plus only (gated in M7). Clamped to `customRange` when read.
    case custom(minutes: Int)

    /// The presets everyone gets, in the order they're offered.
    public static let standard: [SessionPreset] = [.twentyFive, .fifty, .ninety]

    /// Custom lengths run from a minute up to the 4-hour session cap.
    public static let customRange: ClosedRange<Int> = 1...Int(LiveActivityLimits.maxSessionSeconds / 60)

    /// The matching standard preset, or a custom one clamped to `customRange`. For reading back a
    /// saved length.
    public init(minutes: Int) {
        let length = Self.clamped(minutes)
        self = Self.standard.first { $0.minutes == length } ?? .custom(minutes: length)
    }

    public var minutes: Int {
        switch self {
        case .twentyFive: 25
        case .fifty: 50
        case .ninety: 90
        case .custom(let minutes): Self.clamped(minutes)
        }
    }

    public var duration: TimeInterval {
        TimeInterval(minutes * 60)
    }

    /// Custom lengths are a Plus feature; whether the user has Plus is checked by the paywall (M7).
    public var requiresPlus: Bool {
        switch self {
        case .custom: true
        case .twentyFive, .fifty, .ninety: false
        }
    }

    public var id: SessionPreset {
        self
    }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, customRange.lowerBound), customRange.upperBound)
    }
}
