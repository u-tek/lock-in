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
            // Every screen speaks SF Rounded, system controls included (DesignSystem's type).
            .fontDesign(.rounded)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}
