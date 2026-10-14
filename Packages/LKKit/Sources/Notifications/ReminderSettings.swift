import Core
import Foundation

/// The two local reminders' switches (SPEC.md §5.7, docs/milestones/M6.md): "Streak at risk" at a
/// time you pick, and Monday's "Weekly recap". Settings › Notifications › Reminders.
///
/// Kept in the App Group's defaults beside quiet hours (`load` / `save`); the app plans the
/// reminders again whenever they change (`ReminderPlanner`).
public struct ReminderSettings: Codable, Hashable, Sendable {
    /// Both on, the streak reminder at 19:00.
    public static let `default` = ReminderSettings(streakEnabled: true, streakTime: 19 * 60, recapEnabled: true)

    /// The key in the App Group's defaults.
    public static let defaultsKey = "LKReminderSettings"

    /// "Streak at risk": once a day, when a streak hasn't counted yet.
    public var streakEnabled: Bool
    /// When it comes, in minutes after local midnight (0–1439). Inside quiet hours it comes just
    /// before they start instead (`ReminderPlanner.deliveryMinute(_:quietHours:)`).
    public var streakTime: Int {
        didSet { streakTime = QuietHours.normalised(streakTime) }
    }
    /// "Weekly recap": Monday at 09:00.
    public var recapEnabled: Bool

    /// Minutes outside 0–1439 wrap round the clock.
    public init(streakEnabled: Bool = true, streakTime: Int = 19 * 60, recapEnabled: Bool = true) {
        self.streakEnabled = streakEnabled
        self.streakTime = QuietHours.normalised(streakTime)
        self.recapEnabled = recapEnabled
    }

    // MARK: - Storage

    /// What was saved last, or the default (both on, 19:00) when nothing was or it can't be read.
    public static func load(from defaults: UserDefaults? = AppGroup.defaults()) -> ReminderSettings {
        guard let data = (defaults ?? .standard).data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(ReminderSettings.self, from: data)
        else { return .default }
        return saved
    }

    public func save(to defaults: UserDefaults? = AppGroup.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        (defaults ?? .standard).set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case streakEnabled, streakTime, recapEnabled
    }

    /// Lenient: a missing or odd value reads as the default's.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReminderSettings.default
        self.init(
            streakEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .streakEnabled)) ?? fallback.streakEnabled,
            streakTime: (try? container.decodeIfPresent(Int.self, forKey: .streakTime)) ?? fallback.streakTime,
            recapEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .recapEnabled)) ?? fallback.recapEnabled
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(streakEnabled, forKey: .streakEnabled)
        try container.encode(streakTime, forKey: .streakTime)
        try container.encode(recapEnabled, forKey: .recapEnabled)
    }
}

/// The non-session notifications this phone has had, and has coming, so no day gets more than
/// `dailyLimit` of them (SPEC.md §5.7: "never more than ~2 non-session notifications a day").
/// Squad alerts ("is locking in") and the Live Activity aren't counted: they're the session.
///
/// A local notification runs no code when it arrives, so the log is kept as reminders are
/// scheduled: one entry per reminder, at the time it comes. Planning again replaces every entry
/// still to come (`replaceUpcoming(with:at:)`); one whose time has passed was delivered, and is
/// kept for a week. Kept in the App Group's defaults.
public struct ReminderLog: Codable, Hashable, Sendable {
    /// The key in the App Group's defaults.
    public static let defaultsKey = "LKReminderLog"
    /// Non-session notifications a day, at most.
    public static let dailyLimit = 2
    /// How long a delivered notification stays in the log: long enough for any day it can count
    /// against, short enough that the log stays a handful of entries.
    static let keep: TimeInterval = 8 * 24 * 3_600

    public struct Entry: Codable, Hashable, Sendable {
        /// `ReminderKind`'s raw value, or another non-session notification's name.
        public var kind: String
        /// When it comes (or came), Unix seconds.
        public var at: Double

        public init(kind: String, at: Double) {
            self.kind = kind
            self.at = at
        }

        public var date: Date {
            Date(timeIntervalSince1970: at)
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Notifications already delivered by `now` on the local day of `day`. What's still to come
    /// isn't counted: planning replaces it.
    public func delivered(onDayOf day: Date, before now: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        entries.filter { entry in
            entry.date <= now && calendar.isDate(entry.date, inSameDayAs: day)
        }.count
    }

    /// The log after planning `planned` at `now`: what was delivered stays (for a week), and
    /// what's to come is `planned`.
    public mutating func replaceUpcoming(with planned: [PlannedReminder], at now: Date) {
        let delivered = entries.filter { entry in
            entry.date <= now && now.timeIntervalSince(entry.date) < Self.keep
        }
        let upcoming = planned
            .filter { $0.fireDate > now }
            .map { Entry(kind: $0.kind.rawValue, at: $0.fireDate.timeIntervalSince1970) }
        entries = (delivered + upcoming).sorted { $0.at < $1.at }
    }

    /// Notes a non-session notification that isn't a reminder (one a later version adds), so it
    /// counts towards its day's limit.
    public mutating func record(kind: String, at date: Date) {
        entries.append(Entry(kind: kind, at: date.timeIntervalSince1970))
        entries.sort { $0.at < $1.at }
    }

    // MARK: - Storage

    /// What was saved last, or an empty log.
    public static func load(from defaults: UserDefaults? = AppGroup.defaults()) -> ReminderLog {
        guard let data = (defaults ?? .standard).data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(ReminderLog.self, from: data)
        else { return ReminderLog() }
        return saved
    }

    public func save(to defaults: UserDefaults? = AppGroup.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        (defaults ?? .standard).set(data, forKey: Self.defaultsKey)
    }
}
