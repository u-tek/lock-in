import SwiftUI
import WidgetKit

/// The widget extension: the Live Activity (M1), the Squad pet and Lock in widgets, and the
/// Control Center control (M6).
@main
struct LockinWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LockinLiveActivity()
        SquadPetWidget()
        LockInWidget()
        LockInControl()
    }
}
