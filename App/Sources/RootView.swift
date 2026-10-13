import Core
import DesignSystem
import SwiftUI

/// Home, with the Developer menu and its tools pushed on top. M1 puts onboarding and the session
/// screen here.
struct RootView: View {
    @State private var path: [AppRoute] = []
    private let configuration = AppConfiguration.main

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(showsDeveloperTools: configuration.developerToolsEnabled)
                .navigationDestination(for: AppRoute.self) { route in
                    route.destination
                }
        }
        .onOpenURL { url in
            open(url)
        }
    }

    private func open(_ url: URL) {
        guard let link = DeepLink(url: url) else {
            Log.app.info("Ignored a link the app doesn't handle")
            return
        }
        switch link {
        case .session:
            // In M0 the only Live Activities come from the APNs spike, so tapping one goes back
            // to the screen that started it. M1: the session screen.
            guard configuration.developerToolsEnabled else { return }
            path = [.developer, .apnsSpike]
        }
    }
}
