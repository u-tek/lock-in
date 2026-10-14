import Foundation

/// One DeviceActivity interval, as dates. `DeviceActivityMonitoring` turns it into a
/// `DeviceActivitySchedule`.
///
/// DeviceActivity's rules (DeviceActivityCenter.MonitoringError):
/// - An interval must be at least 15 minutes long (`intervalTooShort`) and at most a week
///   (`intervalTooLong`).
/// - An app and its extensions may monitor at most 20 activities; Deep Focus uses two.
/// - Monitoring a name again replaces its schedule. If now falls inside the interval,
///   `intervalDidStart` is called straight away; `intervalDidEnd` comes at the end, but only once
///   the device is in use, and also when monitoring stops during the interval.
///
/// A session can have less than 15 minutes left (resumed late, or a short preset). Rather than go
/// without a schedule, the interval starts in the past: it still ends with the session, and now
/// falls inside it, so it counts as ongoing. If DeviceActivity refuses even that, the shields are
/// already up and the app lifts them itself (`DeepFocusStartOutcome.shieldingWhileLockinRuns`).
struct DeepFocusSchedule: Equatable, Sendable {
    var start: Date
    var end: Date

    /// DeviceActivity's documented minimum interval.
    static let minimumInterval: TimeInterval = 15 * 60
    /// Added to the minimum when an interval is stretched back, so rounding never lands it a
    /// second short.
    static let margin: TimeInterval = 60
    /// Schedules are written as times of day (below), so an interval must stay well under a day.
    /// Sessions are at most 4 hours between pauses; 8 is a Live Activity's whole life.
    static let maximumInterval: TimeInterval = 8 * 3_600

    /// An interval that ends at `end` (whole seconds, rounded up so it never ends early), starts
    /// now or earlier, and is long enough for DeviceActivity. Nil when `end` has passed.
    static func ending(at end: Date, now: Date) -> DeepFocusSchedule? {
        guard end > now else { return nil }
        let cappedEnd = min(end, now.addingTimeInterval(maximumInterval))
        let endSeconds = cappedEnd.timeIntervalSince1970.rounded(.up)
        let startSeconds = min(
            now.timeIntervalSince1970.rounded(.down),
            endSeconds - (minimumInterval + margin)
        )
        return DeepFocusSchedule(
            start: Date(timeIntervalSince1970: startSeconds),
            end: Date(timeIntervalSince1970: endSeconds)
        )
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// The start and end as hour, minute and second in `calendar`, as DeviceActivity takes them.
    ///
    /// Times of day rather than full dates: the interval is the next one these describe, or the
    /// one in progress, and a start date in the past would match no future date
    /// (`invalidDateComponents`). An interval that crosses midnight works the same way. No calendar
    /// is set on the components, so DeviceActivity uses `Calendar.current`, which is what the app
    /// passes here.
    func components(in calendar: Calendar) -> (start: DateComponents, end: DateComponents) {
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        return (calendar.dateComponents(parts, from: start), calendar.dateComponents(parts, from: end))
    }
}
