import Core
import Foundation

/// What the Home and Lock Screen widgets show (docs/milestones/M6.md, "Widget data").
///
/// The widget extension has no network, so the app writes this to the App Group whenever any of it
/// changes (`WidgetDataStore`), then reloads the widgets' timelines. A few hundred bytes of JSON.
///
/// Like `LockinAttributes`, Codable is synthesised and times are `Double` Unix seconds, so the file
/// reads the same in the app and the extension whatever versions they are. New fields go in as
/// optionals, so an extension never fails to read a newer app's file.
public struct WidgetData: Codable, Hashable, Sendable {
    /// Your Lockling's code (`AvatarCode`).
    public var avatar: String
    /// Focused today, solo and squad, in whole minutes.
    public var todayMinutes: Int
    /// Your own days in a row (`FocusStats.streakDays`).
    public var soloStreak: Int
    /// Your squads, in the order you joined them: up to `maxSquads`.
    public var squads: [Squad]
    /// The session running now, so widgets can say "Locked in".
    public var session: Session?
    /// When the app wrote this, Unix seconds.
    public var updatedAt: Double

    public struct Squad: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// `PetCode`, e.g. "sprout.2". An egg is stage 0.
        public var pet: String
        /// 0 sad, 1 hungry, 2 content, 3 happy (`PetMood`).
        public var mood: Int
        /// Progress to the pet's next stage, 0–1.
        public var progress: Double
        /// The squad's days in a row.
        public var streak: Int
        /// Today already counts for the squad's streak.
        public var countedToday: Bool
        /// In the squad's open room right now.
        public var lockedIn: Int

        public init(
            id: String,
            name: String,
            pet: String,
            mood: Int,
            progress: Double,
            streak: Int,
            countedToday: Bool,
            lockedIn: Int
        ) {
            self.id = id
            self.name = name
            self.pet = pet
            self.mood = mood
            self.progress = progress
            self.streak = streak
            self.countedToday = countedToday
            self.lockedIn = lockedIn
        }

        public var petCode: PetCode {
            PetCode(pet)
        }

        /// `mood` held to 0–3.
        public var petMood: PetMood {
            PetMood(level: mood)
        }

        /// `progress` held to 0–1.
        public var clampedProgress: Double {
            progress.isFinite ? min(max(progress, 0), 1) : 0
        }
    }

    public struct Session: Codable, Hashable, Sendable {
        /// When the timer runs out, Unix seconds. While paused, the time left is `endsAt - pausedAt`.
        public var endsAt: Double
        /// When it was paused, Unix seconds. Only while paused.
        public var pausedAt: Double?
        /// The squad it's with; nil when solo.
        public var squadName: String?

        public init(endsAt: Double, pausedAt: Double? = nil, squadName: String? = nil) {
            self.endsAt = endsAt
            self.pausedAt = pausedAt
            self.squadName = squadName
        }

        public var endDate: Date {
            Date(timeIntervalSince1970: endsAt)
        }

        public var pausedDate: Date? {
            pausedAt.map { Date(timeIntervalSince1970: $0) }
        }

        public var isPaused: Bool {
            pausedAt != nil
        }

        /// Seconds left at `date`, never negative. A paused timer is frozen where it stopped.
        public func remaining(at date: Date) -> TimeInterval {
            let reference = pausedAt ?? date.timeIntervalSince1970
            guard endsAt.isFinite, reference.isFinite else { return 0 }
            return max(0, endsAt - reference)
        }

        /// Still going at `date`: paused, or running with time left. A timer that ran out while
        /// the app wasn't running reads as over, before the app has written that it is.
        public func isOngoing(at date: Date) -> Bool {
            isPaused || remaining(at: date) > 0
        }
    }

    public init(
        avatar: String = AvatarCode.default.code,
        todayMinutes: Int = 0,
        soloStreak: Int = 0,
        squads: [Squad] = [],
        session: Session? = nil,
        updatedAt: Double = 0
    ) {
        self.avatar = avatar
        self.todayMinutes = todayMinutes
        self.soloStreak = soloStreak
        self.squads = Array(squads.prefix(Self.maxSquads))
        self.session = session
        self.updatedAt = updatedAt
    }

    /// Squads written: a free account has one, Plus three (SPEC.md §1.6).
    public static let maxSquads = 3

    /// Nothing written yet: the default Lockling, no streak, no squads.
    public static let empty = WidgetData()

    public var avatarCode: AvatarCode {
        AvatarCode(avatar)
    }

    public var updatedDate: Date {
        Date(timeIntervalSince1970: updatedAt)
    }

    public func squad(id: String) -> Squad? {
        squads.first { $0.id == id }
    }

    /// Everything but `updatedAt` is the same: nothing a widget shows has changed.
    public func hasSameContent(as other: WidgetData) -> Bool {
        var mine = self
        mine.updatedAt = other.updatedAt
        return mine == other
    }

    // MARK: - Days

    /// What this data says at `date`, which may be days after the app wrote it.
    ///
    /// The app can't write at midnight, so a widget asks for the day it's drawing. On a later day
    /// than `updatedAt`'s: today's minutes are 0, no squad's today counts yet and every pet is
    /// hungry (the sad half hour after a slip is long over). A streak whose last counted day is
    /// before yesterday has broken and reads 0, as the server and `FocusStats` count it: the solo
    /// streak counted today when `todayMinutes` reached `soloStreakMinutes`, a squad's when
    /// `countedToday` was set. The same day (or an earlier one, a clock set back) changes nothing.
    public func asSeen(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> WidgetData {
        let written = calendar.startOfDay(for: updatedDate)
        let today = calendar.startOfDay(for: date)
        guard today > written, let days = calendar.dateComponents([.day], from: written, to: today).day, days > 0 else {
            return self
        }
        var seen = self
        // Counted on the day it was written: still alive tomorrow, gone the day after. Not counted
        // then: it ran up to the day before, so a day later it's broken.
        let soloAlive = todayMinutes >= Self.soloStreakMinutes ? days <= 1 : false
        seen.soloStreak = soloAlive ? soloStreak : 0
        seen.todayMinutes = 0
        seen.squads = squads.map { squad in
            var squad = squad
            let alive = squad.countedToday ? days <= 1 : false
            squad.streak = alive ? squad.streak : 0
            squad.countedToday = false
            squad.mood = PetMood.hungry.rawValue
            return squad
        }
        return seen
    }

    /// A day keeps your own streak going from this many focused minutes (`FocusStats`' rule, a
    /// session of 20 minutes, `PetRules.streakMinMinutes`).
    public static let soloStreakMinutes = PetRules.streakMinMinutes

    // MARK: - JSON

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(WidgetData.self, from: json)
    }
}

/// Where `WidgetData` lives: `widget.json` in the App Group's widget directory, which the app
/// writes and the widget extension reads.
///
/// Written atomically, and readable once the phone has been unlocked after a restart: Lock Screen
/// widgets draw while the phone is locked, so the file can't use complete protection.
public struct WidgetDataStore: Sendable {
    public static let fileName = "widget.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `widget.json` in the App Group, or in Application Support when the App Group isn't available
    /// (an unsigned simulator build, where the extension can't read it anyway).
    public static func appGroup(configuration: AppConfiguration = .main) -> WidgetDataStore {
        let directory: URL
        do {
            directory = try AppGroup.directory(.widget, configuration: configuration)
        } catch {
            Log.app.error("Widget directory unavailable; using the container's root")
            directory = AppGroup.containerURL(configuration: configuration)
                .appendingPathComponent(AppGroup.Directory.widget.rawValue, isDirectory: true)
        }
        return WidgetDataStore(url: directory.appendingPathComponent(fileName))
    }

    /// What the app wrote last, or nil when it hasn't (or the file can't be read).
    public func load() -> WidgetData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetData(json: data)
    }

    /// Writes `data`. Returns whether it worked; a widget showing yesterday's numbers is the worst
    /// that a failure does.
    @discardableResult
    public func save(_ data: WidgetData) -> Bool {
        do {
            let json = try data.encoded()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #if os(iOS)
            try json.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try json.write(to: url, options: [.atomic])
            #endif
            return true
        } catch {
            Log.app.error("Couldn't write the widgets' data")
            return false
        }
    }
}
