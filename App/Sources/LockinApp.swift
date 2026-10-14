import Core
import DesignSystem
import SwiftUI

@main
struct LockinApp: App {
    @UIApplicationDelegateAdaptor(LockinAppDelegate.self) private var appDelegate

    /// Nil in snapshot mode, which never touches ActivityKit, StoreKit, the App Group, the
    /// Keychain, the network or the notification prompt: its screens make preview models of their
    /// own.
    private let services: LiveServices?

    init() {
        if SnapshotMode.current == nil {
            // CI's filmed squad session skips onboarding (scripts/island-demo.sh).
            IslandDemo.prepare()
            AppServices.noteOrphanedActivities()
            let services = LiveServices()
            AppServices.live = services
            self.services = services
        } else {
            services = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let snapshot = SnapshotMode.current {
                    SnapshotHost(mode: snapshot)
                } else if let services {
                    RootView(engine: services.engine, plus: services.plus, social: services.social)
                        .task {
                            await services.endOrphanedActivities()
                        }
                        .task {
                            await services.plus.load()
                        }
                        .task {
                            // The saved session: still good, signed out elsewhere, or deleted.
                            await services.social.account.restore()
                        }
                        .task {
                            await services.watchLiveActivitySettings()
                        }
                        .task {
                            await services.watchPushToStartTokens()
                        }
                        .task {
                            await IslandDemo.shared.run(controller: AppServices.liveActivities)
                        }
                        .overlay {
                            if IslandDemo.isRequested {
                                IslandDemoMarker()
                            }
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
