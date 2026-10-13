import Foundation

/// The numbers the Live Activity is designed around (SPEC.md §3, §4.3, §4.4). The server holds the
/// same values; change both together.
public enum LiveActivityLimits {
    /// Our cap on attributes + content-state, as compact UTF-8 JSON. The server rejects anything
    /// bigger, leaving headroom under the system's limit.
    public static let payloadBudgetBytes = 3_584
    /// The system's limit on attributes + content-state combined.
    public static let systemLimitBytes = 4_096
    /// Members in one content-state: a Plus squad of 6.
    public static let maxMembers = 6
    /// Display names and squad names are measured in Unicode scalars (see `fitted(_:maxLength:)`).
    public static let maxNameLength = 12
    public static let maxSquadNameLength = 20
    /// Sessions are capped at 4 hours: a Live Activity only stays in the Dynamic Island for 8.
    public static let maxSessionSeconds: TimeInterval = 4 * 3_600
    /// The activity goes stale this long after the last running timer should have ended, so a
    /// missed push shows as out of date rather than wrong.
    public static let staleGraceSeconds: TimeInterval = 300
    /// An ended activity stays on the Lock Screen this long (`dismissal-date` = end + 30 min).
    public static let dismissalAfterEndSeconds: TimeInterval = 1_800

    /// A display name trimmed and cut to `maxNameLength`.
    public static func fittedName(_ name: String) -> String {
        fitted(name, maxLength: maxNameLength)
    }

    /// A squad name trimmed and cut to `maxSquadNameLength`.
    public static func fittedSquadName(_ name: String) -> String {
        fitted(name, maxLength: maxSquadNameLength)
    }

    /// Trims whitespace and keeps whole characters while the total stays within `maxLength`
    /// Unicode scalars.
    ///
    /// Scalars, not characters, because a single character can hold any number of combining marks
    /// or emoji joiners: counting characters would let a 12-character name blow the payload budget.
    /// Whole characters are kept so a family emoji is never cut into its parts.
    public static func fitted(_ text: String, maxLength: Int) -> String {
        var result = ""
        var used = 0
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            let cost = character.unicodeScalars.count
            guard used + cost <= maxLength else { break }
            result.append(character)
            used += cost
        }
        // A cut can land just after a space.
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
