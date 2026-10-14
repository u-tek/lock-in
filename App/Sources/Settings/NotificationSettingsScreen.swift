import Core
import DesignSystem
import Notifications
import SwiftUI
import UIKit
import UserNotifications

/// Settings › Notifications (M4): whether squad alerts can show at all, which the system decides,
/// the two reminders (M6), and quiet hours, which the server keeps to. Like a page of Settings: a
/// status row, switches and times.
struct NotificationSettingsScreen: View {
    @StateObject private var model: NotificationSettingsModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// The real thing: asks the system, and saves and sends quiet hours.
    init() {
        _model = StateObject(wrappedValue: NotificationSettingsModel())
    }

    /// A fixed state, for snapshots: nothing asks the system or touches the App Group.
    init(
        snapshot status: NotificationPermission.Status,
        quietHours: QuietHours = .default,
        reminders: ReminderSettings = .default
    ) {
        _model = StateObject(wrappedValue: NotificationSettingsModel(snapshot: status, quietHours: quietHours, reminders: reminders))
    }

    var body: some View {
        Form {
            Section {
                alerts
            } footer: {
                Text(alertsFooter)
            }

            Section {
                Toggle("Streak reminder", isOn: $model.reminders.streakEnabled)
                if model.reminders.streakEnabled {
                    DatePicker("Time", selection: timeOfDay($model.reminders.streakTime), displayedComponents: .hourAndMinute)
                }
                Toggle("Weekly recap", isOn: $model.reminders.recapEnabled)
            } header: {
                Text("Reminders")
            } footer: {
                Text(remindersFooter)
            }

            Section {
                Toggle("Quiet hours", isOn: $model.quietHours.isEnabled)
                if model.quietHours.isEnabled {
                    DatePicker("From", selection: timeOfDay($model.quietHours.start), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: timeOfDay($model.quietHours.end), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("No squad alerts or reminders during quiet hours.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refresh()
        }
        // Back from Settings, where they may have been switched on or off.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }

    @ViewBuilder
    private var alerts: some View {
        switch model.status {
        case .unknown:
            LabeledContent("Squad alerts") {
                ProgressView()
            }
        case .authorised:
            LabeledContent("Squad alerts", value: "On")
        case .denied:
            LabeledContent("Squad alerts", value: "Off")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            }
        case .notAsked:
            Button("Turn on squad alerts") {
                Task { await model.ask() }
            }
            .disabled(model.isAsking)
        }
    }

    private var alertsFooter: String {
        switch model.status {
        case .unknown, .authorised: "When someone in your squad locks in."
        case .denied: "Turn on notifications for Lockin in Settings."
        case .notAsked: "Know when your squad locks in."
        }
    }

    /// What the reminders are, and when the streak reminder really comes if quiet hours move it.
    private var remindersFooter: String {
        let about = "A nudge when a streak hasn't counted yet that day, and a recap of your week on Monday morning. Two a day at most."
        let streak = model.reminders
        guard streak.streakEnabled else { return about }
        guard let minute = ReminderPlanner.deliveryMinute(streak.streakTime, quietHours: model.quietHours) else {
            return about + " Quiet hours leave no time for the streak reminder."
        }
        guard minute != streak.streakTime else { return about }
        let time = QuietHours.date(minutes: minute).formatted(date: .omitted, time: .shortened)
        return about + " That's in quiet hours, so it comes at \(time)."
    }

    /// Minutes after midnight as the time a picker shows.
    private func timeOfDay(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { QuietHours.date(minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = QuietHours.minutes(of: $0) }
        )
    }
}

/// The screen's state: the system's answer; the reminders, saved to the App Group; and quiet
/// hours, saved to the App Group and sent to the server with the device's registration. The
/// reminders are planned again whenever either changes.
@MainActor
final class NotificationSettingsModel: ObservableObject {
    @Published private(set) var status: NotificationPermission.Status
    @Published private(set) var isAsking = false
    @Published var quietHours: QuietHours {
        didSet {
            if quietHours != oldValue {
                save()
            }
        }
    }
    @Published var reminders: ReminderSettings {
        didSet {
            if reminders != oldValue {
                saveReminders()
            }
        }
    }

    private let isSnapshot: Bool

    init() {
        status = .unknown
        quietHours = QuietHours.load()
        reminders = ReminderSettings.load()
        isSnapshot = false
    }

    init(snapshot status: NotificationPermission.Status, quietHours: QuietHours, reminders: ReminderSettings) {
        self.status = status
        self.quietHours = quietHours
        self.reminders = reminders
        isSnapshot = true
    }

    func refresh() async {
        guard !isSnapshot else { return }
        let current = await NotificationPermission.status()
        if current != status {
            status = current
        }
    }

    /// The system's prompt, the same one onboarding shows.
    func ask() async {
        guard !isSnapshot, !isAsking else { return }
        isAsking = true
        defer { isAsking = false }
        let allowed = await NotificationPermission.request()
        AppServices.analytics.track(allowed ? .notificationsAllowed : .notificationsDeclined)
        await refresh()
    }

    private func save() {
        guard !isSnapshot else { return }
        quietHours.save()
        // The server holds alerts back; it hears with the next registration, which is now.
        AppServices.live?.registerDevice()
        AppServices.live?.widgets.reminders.reschedule()
    }

    private func saveReminders() {
        guard !isSnapshot else { return }
        reminders.save()
        AppServices.live?.widgets.reminders.reschedule()
    }
}

extension NotificationPermission {
    /// Whether alerts can show, as far as the app needs to know.
    enum Status: Equatable, Sendable {
        /// Not read yet.
        case unknown
        /// Never asked: the system's prompt is still to come.
        case notAsked
        case authorised
        /// Turned down, or switched off since: only Settings can change it.
        case denied
    }

    /// The system's current answer. Not on the main actor, like `request()`.
    static func status() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorised
        @unknown default: return .authorised
        }
    }
}
