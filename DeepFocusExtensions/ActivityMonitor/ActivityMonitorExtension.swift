import DeepFocus
import DeviceActivity
import Foundation

/// Puts Deep Focus's shields up when a session's schedule starts and takes them down when it ends,
/// so a session still ends on time when Lockin has been killed. Also shields an app again when its
/// "Open anyway" grace (`.lockinGrace`) runs out.
///
/// Every callback syncs with the state the app recorded rather than applying or clearing blindly:
/// `intervalDidEnd` also comes when the app stops or replaces a schedule (a pause, a resume, a new
/// session), and `intervalDidStart` comes straight away for a schedule already under way. Whatever
/// the reason, the shields end up as the state says: up while a session runs, less the apps on a
/// grace, and down otherwise.
///
/// Monitor extensions get very little memory (reportedly about 6 MB), so this reads two small
/// files and does nothing else.
final class ActivityMonitorExtension: DeviceActivityMonitor {
    private let engine = DeepFocusEngine.live()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        engine.sync()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        engine.sync()
    }
}
