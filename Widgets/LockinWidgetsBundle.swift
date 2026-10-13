import SwiftUI
import WidgetKit

/// The widget extension. M0 has the Live Activity only; the Home and Lock Screen widgets and the
/// Control Center control arrive in M6.
@main
struct LockinWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LockinLiveActivity()
    }
}
