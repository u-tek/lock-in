import Core
import DesignSystem
import SwiftUI

@main
struct LockinApp: App {
    init() {
        // Snapshot mode never touches ActivityKit.
        if SnapshotMode.current == nil {
            AppServices.noteOrphanedActivities()
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let snapshot = SnapshotMode.current {
                    SnapshotHost(mode: snapshot)
                } else {
                    RootView()
                        .task {
                            await AppServices.endOrphanedActivities()
                        }
                }
            }
            // The one brand colour, set once (design/SYSTEM.md): every control, link and toggle
            // below picks it up. The asset catalogue's AccentColor matches it for anything the
            // system draws before SwiftUI does. No font design and no colour scheme here: text is
            // SF Pro, and every screen follows the phone's light or dark appearance.
            .tint(LKColor.tint)
        }
    }
}
