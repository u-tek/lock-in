import Core
import Foundation
import Notifications
import UserNotifications

/// What a tap on an "is locking in" alert asks the screens to do (M4): Home picks the squad, and
/// a join that didn't go through says why.
///
/// One for the app (`AppServices.notificationInbox`), so Home can watch it from wherever it's
/// built. Snapshots never fill it.
@MainActor
final class NotificationInbox: ObservableObject {
    /// A squad for Home to pick. Each request is new, even for the squad already picked, so
    /// tapping a second alert still closes whatever sheet is open.
    struct SquadRequest: Equatable {
        let squadId: String
        let id = UUID()
    }

    @Published var squadRequest: SquadRequest?
    /// Why Join 25 or Join 50 didn't go through, shown over Home.
    @Published var failure: String?

    func pick(_ squadId: String) {
        squadRequest = SquadRequest(squadId: squadId)
    }
}

/// The notification centre's side of squad alerts.
enum SquadAlerts {
    /// Registers `LK_LOCKIN` with Join 25 and Join 50: foreground buttons, or background ones
    /// while the push-to-start spike's switch is on. Registering again replaces the set.
    @MainActor
    static func registerCategories(joinsInBackground: Bool = JoinWithoutOpening.isEnabled()) {
        UNUserNotificationCenter.current().setNotificationCategories(
            LockinNotificationCategory.all(joinsInBackground: joinsInBackground)
        )
    }
}

extension AppServices {
    /// Waits for `work` to finish or for `limit` to pass, whichever comes first, and says whether
    /// it finished. The work carries on either way: a background notification button has only a
    /// few seconds, and its completion handler mustn't wait longer than that.
    static func wait(for work: Task<Void, Never>, atMost limit: Duration) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let gate = FirstToFinish(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                gate.finish(false)
            }
            Task { @MainActor in
                await work.value
                timer.cancel()
                gate.finish(true)
            }
        }
    }
}

/// Resumes a continuation once, for whichever of two tasks gets there first.
@MainActor
private final class FirstToFinish {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ finished: Bool) {
        continuation?.resume(returning: finished)
        continuation = nil
    }
}
