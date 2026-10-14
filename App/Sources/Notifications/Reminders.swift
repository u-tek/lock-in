import API
import Core
import Foundation
import Model
import Notifications
import SessionEngine
import Social
import UserNotifications

/// Schedules the two local reminders (M6, SPEC.md §5.7): "Streak at risk" and Monday's "Weekly
/// recap". `ReminderPlanner` works out what to schedule; this hands it to the notification centre.
///
/// The widgets' writer calls `update(for:)` with every state it builds, so the reminders follow
/// whatever the widgets show: a day that counts takes today's streak reminder back, and the recap
/// carries the week's minutes as of the last change. Settings › Notifications calls
/// `reschedule()` when the reminders or quiet hours change. The notification centre is only
/// touched when the plan changes.
@MainActor
final class ReminderScheduler {
    private weak var engine: SessionEngine?
    private weak var squads: SquadsStore?
    private weak var account: AccountStore?
    private let calendar: Calendar
    private let now: () -> Date
    /// The widgets' latest state.
    private var data: WidgetData?
    /// What the notification centre has, as far as this launch knows. Nil until the first plan,
    /// so a launch always replaces what an earlier one scheduled.
    private var scheduled: [PlannedReminder]?
    /// The notification centre's work, one plan at a time in order.
    private var work: Task<Void, Never>?

    init(calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = Date.init) {
        self.calendar = calendar
        self.now = now
    }

    /// Where the recap's minutes and leaderboard place come from.
    func watch(engine: SessionEngine, social: SocialModels) {
        self.engine = engine
        squads = social.squads
        account = social.account
    }

    /// Plans again from the widgets' latest state.
    func update(for data: WidgetData) {
        self.data = data
        reschedule()
    }

    /// Plans again from the last state, with the settings and quiet hours as saved now.
    func reschedule() {
        guard let data else { return }
        let date = self.now()
        let settings = ReminderSettings.load()
        let quietHours = QuietHours.load()
        var log = ReminderLog.load()
        let recap = settings.recapEnabled ? recapFacts(quietHours: quietHours, now: date) : nil
        let plan = ReminderPlanner.plan(
            data: data,
            settings: settings,
            quietHours: quietHours,
            log: log,
            recap: recap,
            now: date,
            calendar: self.calendar
        )
        guard plan != scheduled else { return }
        scheduled = plan
        log.replaceUpcoming(with: plan, at: date)
        log.save()

        let previous = work
        let triggerCalendar = self.calendar
        work = Task {
            await previous?.value
            await Self.schedule(plan, calendar: triggerCalendar)
        }
    }

    /// The next recap and what it says: this phone's minutes in its week, and your place in the
    /// first squad whose leaderboard for that week the app has seen.
    private func recapFacts(quietHours: QuietHours, now: Date) -> RecapFacts? {
        guard let slot = ReminderPlanner.recapSlot(after: now, quietHours: quietHours, calendar: calendar) else { return nil }
        let minutes = engine?.focusedMinutes(in: slot.week) ?? 0
        return RecapFacts(slot: slot, minutes: minutes, place: place(in: slot.week))
    }

    private func place(in week: DateInterval) -> SquadPlace? {
        guard let squads, let me = account?.user?.id else { return nil }
        for squad in squads.squads {
            guard let board = squads.leaderboards[squad.id],
                  let index = board.entries.firstIndex(where: { $0.userId == me }),
                  board.entries[index].minutes > 0
            else { continue }
            let place = SquadPlace(
                squadName: squad.name,
                place: index + 1,
                of: board.entries.count,
                week: DateInterval(start: board.startDate, end: max(board.startDate, board.endDate))
            )
            if ReminderPlanner.place(place, in: week) != nil {
                return place
            }
        }
        return nil
    }

    /// Replaces every reminder the notification centre has with `plan`. Not on the main actor:
    /// the notification centre isn't `Sendable`, so it's made and used here only.
    private nonisolated static func schedule(_ plan: [PlannedReminder], calendar: Calendar) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.body = reminder.body
            content.sound = .default
            content.threadIdentifier = ReminderPlanner.identifierPrefix + reminder.kind.rawValue
            content.interruptionLevel = .active
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                Log.push.error("Couldn't schedule a reminder")
            }
        }
    }
}
