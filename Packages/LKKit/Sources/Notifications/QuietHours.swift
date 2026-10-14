import Core
import Foundation

/// When squad alerts stay away (SPEC.md §5.7): 22:00 to 07:00 on this phone's clock unless the
/// person changes it in Settings › Notifications.
///
/// Times are minutes after local midnight, as the server takes them (`POST /devices`
/// `quietHours: { start, end }`, docs/milestones/M4.md). The server holds the alerts back: it knows
/// the phone's time zone from the same registration. A window whose start is later than its end
/// crosses midnight.
///
/// Kept in the App Group's defaults (`load` / `save`), so it's there for a registration made at
/// any launch.
public struct QuietHours: Codable, Hashable, Sendable {
    public static let minutesPerDay = 24 * 60

    /// 22:00 to 07:00, on.
    public static let `default` = QuietHours(isEnabled: true, start: 22 * 60, end: 7 * 60)

    /// The key in the App Group's defaults.
    public static let defaultsKey = "LKQuietHours"

    public var isEnabled: Bool
    /// From, in minutes after midnight (0–1439).
    public var start: Int {
        didSet { start = Self.normalised(start) }
    }
    /// To, in minutes after midnight (0–1439). Earlier than `start` when the window crosses
    /// midnight.
    public var end: Int {
        didSet { end = Self.normalised(end) }
    }

    /// Minutes outside 0–1439 wrap round the clock: -60 is 23:00, 1440 is midnight.
    public init(isEnabled: Bool = true, start: Int, end: Int) {
        self.isEnabled = isEnabled
        self.start = Self.normalised(start)
        self.end = Self.normalised(end)
    }

    /// The window crosses midnight (22:00 to 07:00).
    public var crossesMidnight: Bool {
        start > end
    }

    /// The window as the server takes it, or nil for none: switched off, or From and To at the
    /// same minute (an empty window, which the server refuses).
    public var window: (start: Int, end: Int)? {
        guard isEnabled, start != end else { return nil }
        return (start, end)
    }

    /// Whether `date` falls inside the window on `calendar`'s clock: from `start` up to, not
    /// including, `end`. Never when switched off.
    public func contains(date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard window != nil else { return false }
        let minute = Self.minutes(of: date, calendar: calendar)
        if crossesMidnight {
            return minute >= start || minute < end
        }
        return minute >= start && minute < end
    }

    // MARK: - Time pickers

    /// The minutes after midnight of `date` on `calendar`'s clock.
    public static func minutes(of date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return normalised((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// `minutes` after midnight on `day`, for a time picker. On the night the clocks change, a
    /// time that doesn't exist that day comes back as the system moves it.
    public static func date(minutes: Int, on day: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Date {
        let minute = normalised(minutes)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
            ?? calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minute * 60))
    }

    static func normalised(_ minutes: Int) -> Int {
        let wrapped = minutes % minutesPerDay
        return wrapped < 0 ? wrapped + minutesPerDay : wrapped
    }

    // MARK: - Storage

    /// What was saved last, or the default (22:00 to 07:00, on) when nothing was, or what was saved
    /// can't be read.
    public static func load(from defaults: UserDefaults? = AppGroup.defaults()) -> QuietHours {
        guard let data = (defaults ?? .standard).data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(QuietHours.self, from: data)
        else { return .default }
        return saved
    }

    public func save(to defaults: UserDefaults? = AppGroup.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        (defaults ?? .standard).set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case isEnabled, start, end
    }

    /// Lenient: a missing or odd value reads as the default's, so a later version's file never
    /// switches quiet hours off by accident.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = QuietHours.default
        self.init(
            isEnabled: (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? fallback.isEnabled,
            start: (try? container.decodeIfPresent(Int.self, forKey: .start)) ?? fallback.start,
            end: (try? container.decodeIfPresent(Int.self, forKey: .end)) ?? fallback.end
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
    }
}
