// WidgetViews: the Home and Lock Screen widgets' looks (M6, docs/milestones/M6.md).
//
// Like the Live Activity's views (docs/decisions/0001-live-activity-views-in-package.md), they live
// in a package module rather than in the widget extension, so the app can draw them too: the
// `widgets.*` snapshot routes render exactly what the extension does. `Widgets/` keeps only the
// system wiring (the widget configurations, timeline providers, the squad picker's entity and
// the Control Center control) and passes in what it reads from the system: the family, the
// rendering mode, the entry's date.
//
// Widget rules, the Live Activity's in short: no network, no images (Locklings and pets are
// shapes), no animation (the system ignores it), countdowns with `Text(timerInterval:)`, and
// accessory families drawn for one colour.

import Foundation
import Model

/// The widgets' kinds. A kind is what a placed widget remembers: never rename one.
public enum WidgetKind {
    /// The squad pet and its streak; your Lockling and your streak with no squad.
    public static let squadPet = "SquadPet"
    /// Your Lockling and a Lock in button; the countdown while a session runs.
    public static let lockIn = "LockIn"
    /// The Control Center control that starts a session.
    public static let lockInControl = "LockInControl"
}

/// Links the widgets open. The app reads them with `DeepLink` (`App/Sources/AppRoute.swift`);
/// change both together.
public enum WidgetLink {
    public static let scheme = "lockin"

    /// `lockin://squad/<id>`: Home, with that squad picked.
    public static func squad(_ id: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "squad"
        components.path = "/" + id
        return components.url
    }
}

/// The words the widgets use. English only until the app has a string catalogue.
public enum WidgetWords {
    /// "No streak yet", "1 day", "12 days".
    public static func streak(_ days: Int) -> String {
        switch days {
        case ...0: "No streak yet"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    /// "45 min today".
    public static func today(_ minutes: Int) -> String {
        "\(max(0, minutes)) min today"
    }

    /// "3 locked in".
    public static func lockedIn(_ count: Int) -> String {
        "\(count) locked in"
    }

    /// "Happy".
    public static func mood(_ mood: Int) -> String {
        capitalised(PetMood(level: mood).name)
    }

    /// "Sprout · teen", or "Egg": the species is a surprise until it hatches. As the Live
    /// Activity's pet row says it.
    public static func pet(_ code: PetCode) -> String {
        guard code.growth != .egg else { return "Egg" }
        return "\(capitalised(code.species)) · \(code.stageName)"
    }

    /// "14:59", or "1:05:00" from an hour: a paused timer, which doesn't tick.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let rest = total % 60
        let twoDigits = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))"
        }
        return "\(minutes):\(twoDigits(rest))"
    }

    static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + String(text.dropFirst())
    }
}

/// When a widget's look changes without the app writing anything: when a session's timer runs
/// out, and at midnight, when today's minutes and the pets' moods start again
/// (`WidgetData.asSeen(at:calendar:)`). The timeline providers make an entry at each.
public enum WidgetTimeline {
    /// `now`, then each moment after it that changes what `data` shows, in order.
    public static func entryDates(for data: WidgetData, from now: Date, calendar: Calendar = .autoupdatingCurrent) -> [Date] {
        var dates = [now]
        if let session = data.session, !session.isPaused, session.endDate > now {
            dates.append(session.endDate)
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), midnight > now {
            dates.append(midnight)
        }
        return Array(Set(dates)).sorted()
    }
}
